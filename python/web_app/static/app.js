// IPD Control Panel - Frontend JavaScript

let socket = null;
let currentProcesses = {};

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    loadConfig();
    initWebSocket();
    refreshCheckpoints();
    startStatusPolling();
    initForms();
    loadAttributes();
});

// Load default configuration
async function loadConfig() {
    try {
        const response = await fetch('/api/config');
        const config = await response.json();

        document.getElementById('collect-godot-path').value = config.godot_path;
        document.getElementById('collect-project-path').value = config.project_path;
        document.getElementById('train-data-dir').value = config.data_dir;
        document.getElementById('train-output-dir').value = config.checkpoints_dir;
    } catch (error) {
        console.error('Failed to load config:', error);
    }
}

// Initialize WebSocket for real-time logs
function initWebSocket() {
    socket = io();

    socket.on('connect', () => {
        console.log('WebSocket connected');
    });

    socket.on('process_output', (data) => {
        appendConsoleOutput(data.process_id, data.output);
    });

    socket.on('process_complete', (data) => {
        const processType = data.process_id.split('_')[0];
        const statusDiv = document.getElementById(`${processType}-status`);
        const stopBtn = document.getElementById(`stop-${processType}-btn`);

        if (data.exit_code === 0) {
            statusDiv.textContent = 'Completed successfully';
            statusDiv.className = 'status-text';
            appendConsoleOutput(data.process_id, '\n✓ Process completed successfully\n');
        } else {
            statusDiv.textContent = `Failed (exit code: ${data.exit_code})`;
            statusDiv.className = 'status-text error';
            appendConsoleOutput(data.process_id, `\n✗ Process failed with exit code ${data.exit_code}\n`);
        }

        if (stopBtn) {
            stopBtn.disabled = true;
        }
        delete currentProcesses[data.process_id];
    });
}

// Initialize form handlers
function initForms() {
    document.getElementById('collect-form').addEventListener('submit', async (e) => {
        e.preventDefault();
        await startCollection();
    });

    document.getElementById('train-form').addEventListener('submit', async (e) => {
        e.preventDefault();
        await startTraining();
    });

    document.getElementById('inference-form').addEventListener('submit', async (e) => {
        e.preventDefault();
        await startInference();
    });
}

// Tab switching
function switchTab(tabName) {
    // Hide all tabs
    document.querySelectorAll('.tab-content').forEach(tab => {
        tab.classList.remove('active');
    });

    // Deactivate all buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.remove('active');
    });

    // Show selected tab
    document.getElementById(`${tabName}-tab`).classList.add('active');

    // Activate button
    event.target.classList.add('active');
}

// Start data collection
async function startCollection() {
    const statusDiv = document.getElementById('collect-status');
    const consoleDiv = document.getElementById('collect-console');
    const stopBtn = document.getElementById('stop-collect-btn');

    consoleDiv.textContent = '';
    statusDiv.textContent = 'Starting...';
    statusDiv.className = 'status-text running';

    const data = {
        godot_path: document.getElementById('collect-godot-path').value,
        project_path: document.getElementById('collect-project-path').value,
        workers: parseInt(document.getElementById('collect-workers').value),
        episodes_per_worker: parseInt(document.getElementById('collect-episodes').value),
        timescale: parseFloat(document.getElementById('collect-timescale').value),
        output_dir: document.getElementById('collect-output-dir').value || null
    };

    try {
        const response = await fetch('/api/collect/start', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (result.success) {
            statusDiv.textContent = 'Running...';
            currentProcesses[result.process_id] = 'collect';
            stopBtn.disabled = false;
            appendConsoleOutput(result.process_id, `Started data collection (${result.process_id})\n`);
        } else {
            statusDiv.textContent = `Error: ${result.error}`;
            statusDiv.className = 'status-text error';
        }
    } catch (error) {
        statusDiv.textContent = `Error: ${error.message}`;
        statusDiv.className = 'status-text error';
    }
}

// Start training
async function startTraining() {
    const statusDiv = document.getElementById('train-status');
    const consoleDiv = document.getElementById('train-console');
    const stopBtn = document.getElementById('stop-train-btn');

    consoleDiv.textContent = '';
    statusDiv.textContent = 'Starting...';
    statusDiv.className = 'status-text running';

    const data = {
        data_dir: document.getElementById('train-data-dir').value,
        epochs: parseInt(document.getElementById('train-epochs').value),
        batch_size: parseInt(document.getElementById('train-batch-size').value),
        learning_rate: parseFloat(document.getElementById('train-lr').value),
        hidden_dim: parseInt(document.getElementById('train-hidden-dim').value),
        num_heads: parseInt(document.getElementById('train-num-heads').value),
        num_layers: parseInt(document.getElementById('train-num-layers').value),
        dropout: parseFloat(document.getElementById('train-dropout').value),
        output_dir: document.getElementById('train-output-dir').value
    };

    try {
        const response = await fetch('/api/train/start', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (result.success) {
            statusDiv.textContent = 'Training...';
            currentProcesses[result.process_id] = 'train';
            stopBtn.disabled = false;
            appendConsoleOutput(result.process_id, `Started training (${result.process_id})\n`);
        } else {
            statusDiv.textContent = `Error: ${result.error}`;
            statusDiv.className = 'status-text error';
        }
    } catch (error) {
        statusDiv.textContent = `Error: ${error.message}`;
        statusDiv.className = 'status-text error';
    }
}

// Start inference server
async function startInference() {
    const statusDiv = document.getElementById('inference-status');
    const consoleDiv = document.getElementById('inference-console');
    const stopBtn = document.getElementById('stop-inference-btn');

    consoleDiv.textContent = '';
    statusDiv.textContent = 'Starting...';
    statusDiv.className = 'status-text running';

    const checkpointDir = document.getElementById('inference-checkpoint').value;
    if (!checkpointDir) {
        statusDiv.textContent = 'Error: Please select a checkpoint';
        statusDiv.className = 'status-text error';
        return;
    }

    const data = {
        checkpoint_dir: checkpointDir,
        port: parseInt(document.getElementById('inference-port').value)
    };

    try {
        const response = await fetch('/api/inference/start', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (result.success) {
            statusDiv.textContent = 'Running...';
            currentProcesses[result.process_id] = 'inference';
            stopBtn.disabled = false;
            appendConsoleOutput(result.process_id, `Started inference server (${result.process_id})\n`);
        } else {
            statusDiv.textContent = `Error: ${result.error}`;
            statusDiv.className = 'status-text error';
        }
    } catch (error) {
        statusDiv.textContent = `Error: ${error.message}`;
        statusDiv.className = 'status-text error';
    }
}

// Stop process
async function stopProcess(processType) {
    let processId;

    // Find the process ID based on type
    if (processType === 'inference_server') {
        processId = 'inference_server';
    } else {
        processId = Object.keys(currentProcesses).find(id => id.startsWith(processType));
    }

    if (!processId) {
        console.error('No running process found for type:', processType);
        return;
    }

    try {
        const response = await fetch(`/api/process/stop/${processId}`, {
            method: 'POST'
        });

        const result = await response.json();

        if (result.success) {
            const statusDiv = document.getElementById(`${processType}-status`);
            const stopBtn = document.getElementById(`stop-${processType}-btn`);

            statusDiv.textContent = 'Stopped';
            statusDiv.className = 'status-text';
            stopBtn.disabled = true;
            appendConsoleOutput(processId, '\n✓ Process stopped by user\n');
            delete currentProcesses[processId];
        }
    } catch (error) {
        console.error('Failed to stop process:', error);
    }
}

// Refresh checkpoint list
async function refreshCheckpoints() {
    try {
        const response = await fetch('/api/checkpoints/list');
        const checkpoints = await response.json();

        const select = document.getElementById('inference-checkpoint');
        select.innerHTML = '<option value="">Select a checkpoint...</option>';

        checkpoints.forEach(checkpoint => {
            const option = document.createElement('option');
            option.value = checkpoint.path;
            option.textContent = `${checkpoint.name} (${checkpoint.epochs} epochs)`;
            select.appendChild(option);
        });
    } catch (error) {
        console.error('Failed to load checkpoints:', error);
    }
}

// Append console output
function appendConsoleOutput(processId, text) {
    const processType = processId.split('_')[0];
    const consoleDiv = document.getElementById(`${processType}-console`);

    if (consoleDiv) {
        consoleDiv.textContent += text;
        consoleDiv.scrollTop = consoleDiv.scrollHeight;
    }
}

// Load attributes from server
async function loadAttributes() {
    try {
        const response = await fetch('/api/attributes');
        const attrs = await response.json();

        for (const [entity, values] of Object.entries(attrs)) {
            for (const [attr, val] of Object.entries(values)) {
                const input = document.getElementById(`attr-${entity}-${attr}`);
                if (input) {
                    input.value = val;
                }
            }
        }
    } catch (error) {
        console.error('Failed to load attributes:', error);
    }
}

// Save attributes to server
async function saveAttributes() {
    const statusMsg = document.getElementById('attributes-status-msg');
    const entities = ['tank', 'healer', 'sniper', 'boss'];
    const attrs = {};

    for (const entity of entities) {
        attrs[entity] = {};
        const inputs = document.querySelectorAll(`[id^="attr-${entity}-"]`);
        inputs.forEach(input => {
            const attr = input.id.replace(`attr-${entity}-`, '');
            attrs[entity][attr] = parseFloat(input.value);
        });
    }

    try {
        const response = await fetch('/api/attributes', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(attrs)
        });

        const result = await response.json();

        statusMsg.style.display = 'block';
        if (result.success) {
            statusMsg.className = 'status-msg success';
            statusMsg.textContent = 'Attributes saved successfully to GDScript files.';
        } else {
            statusMsg.className = 'status-msg error';
            statusMsg.textContent = `Error: ${result.error}`;
        }

        setTimeout(() => { statusMsg.style.display = 'none'; }, 4000);
    } catch (error) {
        statusMsg.style.display = 'block';
        statusMsg.className = 'status-msg error';
        statusMsg.textContent = `Error: ${error.message}`;
        setTimeout(() => { statusMsg.style.display = 'none'; }, 4000);
    }
}

// Poll process status
function startStatusPolling() {
    setInterval(async () => {
        try {
            const response = await fetch('/api/process/status');
            const status = await response.json();

            // Update stop buttons based on running processes
            Object.keys(currentProcesses).forEach(processId => {
                if (!status[processId] || !status[processId].running) {
                    delete currentProcesses[processId];
                }
            });
        } catch (error) {
            console.error('Failed to poll status:', error);
        }
    }, 5000);
}
