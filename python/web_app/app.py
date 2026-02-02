"""
IPD Control Panel - Web interface for data collection, training, and inference.

Flask web app that provides a dashboard to:
- Run parallel data collection with custom parameters
- Train GAT models
- Manage inference server

Usage:
    python app.py
    Then open http://127.0.0.1:5000 in your browser
"""

import os
import re
import json
import subprocess
import threading
import queue
from pathlib import Path
from datetime import datetime
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit

app = Flask(__name__)
app.config['SECRET_KEY'] = 'ipd-control-panel-secret'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

# Process tracking
active_processes = {}
process_outputs = {}

# Default paths
DEFAULT_GODOT_PATH = r"E:\Godot 4.5.1\Godot.exe"
DEFAULT_PROJECT_PATH = str(Path(__file__).parent.parent.parent.absolute())
DEFAULT_DATA_DIR = str(Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "IPD" / "training_data" / "merged")
SCRIPTS_DIR = Path(DEFAULT_PROJECT_PATH) / "scripts"
ATTRIBUTES_FILE = Path(DEFAULT_PROJECT_PATH) / "attributes.json"


def stream_process_output(process_id, process, output_queue):
    """Stream process output to queue for websocket broadcasting."""
    try:
        for line in iter(process.stdout.readline, ''):
            if line:
                output_queue.put(line)
                socketio.emit('process_output', {
                    'process_id': process_id,
                    'output': line
                }, namespace='/')
        process.wait()
    except Exception as e:
        output_queue.put(f"ERROR: {str(e)}\n")
    finally:
        socketio.emit('process_complete', {
            'process_id': process_id,
            'exit_code': process.returncode
        }, namespace='/')


@app.route('/')
def index():
    """Serve the main dashboard page."""
    return render_template('index.html')


@app.route('/api/config', methods=['GET'])
def get_config():
    """Get default configuration values."""
    return jsonify({
        'godot_path': DEFAULT_GODOT_PATH,
        'project_path': DEFAULT_PROJECT_PATH,
        'data_dir': DEFAULT_DATA_DIR,
        'checkpoints_dir': str(Path(DEFAULT_PROJECT_PATH) / "checkpoints")
    })


@app.route('/api/collect/start', methods=['POST'])
def start_collection():
    """Start parallel data collection."""
    data = request.json

    # Build command
    cmd = [
        'python', '-u',
        str(Path(DEFAULT_PROJECT_PATH) / 'python' / 'parallel_collect.py'),
        '--godot', data.get('godot_path', DEFAULT_GODOT_PATH),
        '--project', data.get('project_path', DEFAULT_PROJECT_PATH),
        '--workers', str(data.get('workers', 4)),
        '--episodes-per-worker', str(data.get('episodes_per_worker', 25)),
        '--timescale', str(data.get('timescale', 3.0))
    ]

    if data.get('output_dir'):
        cmd.extend(['--output', data['output_dir']])

    # Start process
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        process_id = f"collect_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        active_processes[process_id] = process
        process_outputs[process_id] = queue.Queue()

        # Start output streaming thread
        thread = threading.Thread(
            target=stream_process_output,
            args=(process_id, process, process_outputs[process_id])
        )
        thread.daemon = True
        thread.start()

        return jsonify({
            'success': True,
            'process_id': process_id,
            'message': 'Data collection started'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/train/start', methods=['POST'])
def start_training():
    """Start GAT model training."""
    data = request.json

    # Build command
    cmd = [
        'python', '-u',
        str(Path(DEFAULT_PROJECT_PATH) / 'python' / 'train.py'),
        data.get('data_dir', DEFAULT_DATA_DIR),
        '--epochs', str(data.get('epochs', 100)),
        '--batch-size', str(data.get('batch_size', 64)),
        '--lr', str(data.get('learning_rate', 0.001)),
        '--hidden-dim', str(data.get('hidden_dim', 64)),
        '--num-heads', str(data.get('num_heads', 4)),
        '--num-layers', str(data.get('num_layers', 3)),
        '--dropout', str(data.get('dropout', 0.1)),
        '--output-dir', data.get('output_dir', str(Path(DEFAULT_PROJECT_PATH) / 'checkpoints'))
    ]

    # Start process
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        process_id = f"train_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        active_processes[process_id] = process
        process_outputs[process_id] = queue.Queue()

        # Start output streaming thread
        thread = threading.Thread(
            target=stream_process_output,
            args=(process_id, process, process_outputs[process_id])
        )
        thread.daemon = True
        thread.start()

        return jsonify({
            'success': True,
            'process_id': process_id,
            'message': 'Training started'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/inference/start', methods=['POST'])
def start_inference():
    """Start inference server."""
    data = request.json

    checkpoint_dir = data.get('checkpoint_dir')
    if not checkpoint_dir:
        return jsonify({
            'success': False,
            'error': 'Checkpoint directory required'
        }), 400

    # Build command
    cmd = [
        'python', '-u',
        str(Path(DEFAULT_PROJECT_PATH) / 'python' / 'inference_server.py'),
        checkpoint_dir,
        '--port', str(data.get('port', 5555))
    ]

    # Start process
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        process_id = 'inference_server'
        active_processes[process_id] = process
        process_outputs[process_id] = queue.Queue()

        # Start output streaming thread
        thread = threading.Thread(
            target=stream_process_output,
            args=(process_id, process, process_outputs[process_id])
        )
        thread.daemon = True
        thread.start()

        return jsonify({
            'success': True,
            'process_id': process_id,
            'message': 'Inference server started'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/process/stop/<process_id>', methods=['POST'])
def stop_process(process_id):
    """Stop a running process."""
    if process_id in active_processes:
        try:
            process = active_processes[process_id]
            process.terminate()
            process.wait(timeout=5)
            del active_processes[process_id]
            return jsonify({
                'success': True,
                'message': f'Process {process_id} stopped'
            })
        except Exception as e:
            return jsonify({
                'success': False,
                'error': str(e)
            }), 500
    else:
        return jsonify({
            'success': False,
            'error': 'Process not found'
        }), 404


@app.route('/api/process/status', methods=['GET'])
def get_status():
    """Get status of all processes."""
    status = {}
    for process_id, process in list(active_processes.items()):
        poll = process.poll()
        if poll is not None:
            # Process finished
            del active_processes[process_id]
            status[process_id] = {'running': False, 'exit_code': poll}
        else:
            status[process_id] = {'running': True, 'exit_code': None}

    return jsonify(status)


@app.route('/api/checkpoints/list', methods=['GET'])
def list_checkpoints():
    """List available model checkpoints."""
    checkpoints_dir = Path(DEFAULT_PROJECT_PATH) / 'checkpoints'
    if not checkpoints_dir.exists():
        return jsonify([])

    checkpoints = []
    for run_dir in checkpoints_dir.iterdir():
        if run_dir.is_dir() and run_dir.name.startswith('run_'):
            config_path = run_dir / 'config.json'
            if config_path.exists():
                with open(config_path) as f:
                    config = json.load(f)
                checkpoints.append({
                    'name': run_dir.name,
                    'path': str(run_dir),
                    'timestamp': run_dir.name.replace('run_', ''),
                    'epochs': config.get('epochs', 'N/A'),
                    'val_acc': config.get('val_acc', 'N/A')
                })

    return jsonify(sorted(checkpoints, key=lambda x: x['timestamp'], reverse=True))


# --- Attribute definitions: maps each attribute to its file and parsing info ---
ATTR_DEFS = {
    "tank": {
        "file": "tank.gd",
        "attrs": {
            "max_health": {"pattern": r"(max_health\s*=\s*)\d+", "type": int},
            "max_stamina": {"pattern": r"(max_stamina\s*=\s*)\d+", "type": int},
            "speed":       {"pattern": r"(speed\s*=\s*)[\d.]+", "type": float},
            "melee_damage": {"pattern": r"(\.take_damage\()30(\))", "type": int, "replace": r"\g<1>{}\2"},
            "taunt_cost":   {"pattern": r"(stamina\s*-=\s*)15", "type": int, "also": r"(stamina\s*<\s*)15"},
            "defensive_cost": {"pattern": r"(stamina\s*-=\s*)10", "type": int, "also": r"(stamina\s*<\s*)10"},
        }
    },
    "healer": {
        "file": "healer.gd",
        "attrs": {
            "max_health":   {"pattern": r"(max_health\s*=\s*)\d+", "type": int},
            "max_stamina":  {"pattern": r"(max_stamina\s*=\s*)\d+", "type": int},
            "speed":        {"pattern": r"(speed\s*=\s*)[\d.]+", "type": float},
            "heal_amount":  {"pattern": r"(\.heal\()40(\))", "type": int, "replace": r"\g<1>{}\2"},
            "shield_cost":  {"pattern": r"(stamina\s*-=\s*)30", "type": int, "also": r"(stamina\s*<\s*)30"},
            "restore_cost": {"pattern": r"(stamina\s*-=\s*)50", "type": int, "also": r"(stamina\s*<\s*)50"},
            "restore_amount": {"pattern": r"(restore_amount\s*=\s*)\d+", "type": int},
        }
    },
    "sniper": {
        "file": "sniper.gd",
        "attrs": {
            "max_health":    {"pattern": r"(max_health\s*=\s*)\d+", "type": int},
            "max_stamina":   {"pattern": r"(max_stamina\s*=\s*)\d+", "type": int},
            "speed":         {"pattern": r"(speed\s*=\s*)[\d.]+", "type": float},
            "shot_damage":   {"pattern": r"(\.take_damage\()40(\))", "type": int, "replace": r"\g<1>{}\2"},
            "cripple_cost":  {"pattern": r"(stamina\s*-=\s*)40", "type": int, "also": r"(stamina\s*<\s*)40"},
            "cripple_damage": {"pattern": r"(\.take_damage\()25(\))", "type": int, "replace": r"\g<1>{}\2"},
            "power_cost":    {"pattern": r"(stamina\s*-=\s*)60", "type": int, "also": r"(stamina\s*<\s*)60"},
            "power_damage":  {"pattern": r"(\.take_damage\()85(\))", "type": int, "replace": r"\g<1>{}\2"},
        }
    },
    "boss": {
        "file": "boss.gd",
        "attrs": {
            "max_health":   {"pattern": r"(max_health:\s*int\s*=\s*)\d+", "type": int},
            "max_stamina":  {"pattern": r"(max_stamina:\s*int\s*=\s*)\d+", "type": int},
            "speed":        {"pattern": r"(movement_speed:\s*float\s*=\s*)[\d.]+", "type": float},
            "ranged_damage": {"pattern": r"(\.take_damage\()20(\))", "type": int, "replace": r"\g<1>{}\2"},
            "melee_damage":  {"pattern": r"(\.take_damage\()30(\))", "type": int, "replace": r"\g<1>{}\2"},
            "stamina_regen": {"pattern": r"(stamina\s*\+=\s*)15\.0", "type": float},
        }
    },
}


def _read_attributes_from_scripts():
    """Parse current attribute values from GDScript files."""
    result = {}
    for entity, defn in ATTR_DEFS.items():
        filepath = SCRIPTS_DIR / defn["file"]
        if not filepath.exists():
            continue
        content = filepath.read_text(encoding="utf-8")
        result[entity] = {}
        for attr_name, attr_info in defn["attrs"].items():
            match = re.search(attr_info["pattern"], content)
            if match:
                # Extract the value part (what comes after the captured group)
                full = match.group(0)
                prefix = match.group(1)
                value_str = full[len(prefix):]
                # For replace-style patterns the value is embedded differently
                if "replace" in attr_info:
                    # The value is in group position between groups
                    value_str = match.group(0)
                    value_str = value_str.replace(match.group(1), "").replace(match.group(2), "")
                try:
                    result[entity][attr_name] = attr_info["type"](value_str)
                except (ValueError, IndexError):
                    result[entity][attr_name] = 0
            else:
                result[entity][attr_name] = 0
    return result


def _write_attributes_to_scripts(attrs):
    """Write attribute values back to GDScript files."""
    errors = []
    for entity, defn in ATTR_DEFS.items():
        if entity not in attrs:
            continue
        filepath = SCRIPTS_DIR / defn["file"]
        if not filepath.exists():
            errors.append(f"{defn['file']} not found")
            continue
        content = filepath.read_text(encoding="utf-8")
        for attr_name, attr_info in defn["attrs"].items():
            if attr_name not in attrs[entity]:
                continue
            val = attrs[entity][attr_name]
            if attr_info["type"] == float:
                val_str = f"{float(val)}"
            else:
                val_str = str(int(val))

            if "replace" in attr_info:
                replacement = attr_info["replace"].format(val_str)
                content = re.sub(attr_info["pattern"], replacement, content)
            else:
                content = re.sub(attr_info["pattern"], rf"\g<1>{val_str}", content)

            # Also update the guard check if defined
            if "also" in attr_info:
                content = re.sub(attr_info["also"], rf"\g<1>{val_str}", content)

        # Also sync initial health/stamina = max values
        if entity != "boss":
            if "max_health" in attrs[entity]:
                v = int(attrs[entity]["max_health"])
                # Replace the second occurrence: "health = X" in _ready
                lines = content.split("\n")
                found_max = False
                for i, line in enumerate(lines):
                    if re.match(r'\s*max_health\s*=\s*\d+', line):
                        found_max = True
                    elif found_max and re.match(r'\s*health\s*=\s*\d+', line):
                        lines[i] = re.sub(r'(health\s*=\s*)\d+', rf'\g<1>{v}', line)
                        break
                content = "\n".join(lines)
            if "max_stamina" in attrs[entity]:
                v = int(attrs[entity]["max_stamina"])
                lines = content.split("\n")
                found_max = False
                for i, line in enumerate(lines):
                    if re.match(r'\s*max_stamina\s*=\s*\d+', line):
                        found_max = True
                    elif found_max and re.match(r'\s*stamina\s*=\s*\d+', line):
                        lines[i] = re.sub(r'(stamina\s*=\s*)\d+', rf'\g<1>{v}', line)
                        break
                content = "\n".join(lines)
        else:
            # Boss: sync @export var health and stamina defaults
            if "max_health" in attrs[entity]:
                v = int(attrs[entity]["max_health"])
                content = re.sub(r'(@export\s+var\s+health:\s*int\s*=\s*)\d+', rf'\g<1>{v}', content)
                content = re.sub(r'(@export\s+var\s+max_health:\s*int\s*=\s*)\d+', rf'\g<1>{v}', content)
            if "max_stamina" in attrs[entity]:
                v = int(attrs[entity]["max_stamina"])
                content = re.sub(r'(@export\s+var\s+stamina:\s*int\s*=\s*)\d+', rf'\g<1>{v}', content)
                content = re.sub(r'(@export\s+var\s+max_stamina:\s*int\s*=\s*)\d+', rf'\g<1>{v}', content)

        filepath.write_text(content, encoding="utf-8")

    return errors


@app.route('/api/attributes', methods=['GET'])
def get_attributes():
    """Get current game attributes from GDScript files."""
    try:
        attrs = _read_attributes_from_scripts()
        return jsonify(attrs)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/attributes', methods=['POST'])
def save_attributes():
    """Save game attributes to GDScript files."""
    try:
        attrs = request.json
        errors = _write_attributes_to_scripts(attrs)
        # Also save a backup JSON
        with open(ATTRIBUTES_FILE, 'w') as f:
            json.dump(attrs, f, indent=2)
        if errors:
            return jsonify({'success': True, 'warnings': errors})
        return jsonify({'success': True, 'message': 'Attributes saved to scripts'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@socketio.on('connect')
def handle_connect():
    """Handle websocket connection."""
    emit('connected', {'message': 'Connected to IPD Control Panel'})


if __name__ == '__main__':
    print("=" * 60)
    print("IPD Control Panel")
    print("=" * 60)
    print(f"Godot Path:    {DEFAULT_GODOT_PATH}")
    print(f"Project Path:  {DEFAULT_PROJECT_PATH}")
    print(f"Data Dir:      {DEFAULT_DATA_DIR}")
    print("=" * 60)
    print("\nStarting server at http://127.0.0.1:5050")
    print("Press Ctrl+C to stop\n")

    socketio.run(app, host='127.0.0.1', port=5050, debug=False)
