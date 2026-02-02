# IPD Control Panel

A web-based dashboard for managing data collection, training, and inference for the Intelligent Plan Development (IPD) project.

## Features

- **📊 Data Collection Tab**: Run parallel Godot instances to collect MCTS training data
  - Configure number of workers, episodes per worker, and timescale
  - Real-time console output
  - Automatic data merging

- **🧠 Training Tab**: Train Graph Attention Network models
  - Configurable hyperparameters (epochs, batch size, learning rate, etc.)
  - Monitor training progress in real-time
  - Automatic checkpoint saving

- **🚀 Inference Server Tab**: Manage the GAT inference server
  - Select from available trained checkpoints
  - Configure server port
  - Monitor server status and connection logs

## Installation

1. Install the required dependencies:
```bash
cd v1/python/web_app
pip install -r requirements.txt
```

Or run the installer:
```bash
install.bat
```

2. Ensure you have the main project dependencies installed:
```bash
cd v1/python
pip install torch torch-geometric
```

**Note:** This control panel uses threading mode for WebSockets, which is compatible with all Python versions without requiring C extensions.

## Usage

### Starting the Control Panel

Run the Flask application:
```bash
python app.py
```

Or use the batch file (Windows):
```bash
start_control_panel.bat
```

Then open your browser to: [http://127.0.0.1:5050](http://127.0.0.1:5050)

### Data Collection

1. Switch to the **Data Collection** tab
2. Configure the parameters:
   - **Workers**: Number of parallel Godot instances (recommended: 4-8)
   - **Episodes per Worker**: Episodes each worker will collect (default: 25)
   - **Timescale**: Game speed multiplier (default: 3.0x)
3. Click **Start Collection**
4. Monitor progress in the console output
5. Data will be automatically merged into `training_data/merged/`

### Training

1. Switch to the **Training** tab
2. Verify the training data directory path
3. Configure model hyperparameters:
   - **Epochs**: Number of training epochs (default: 100)
   - **Batch Size**: Training batch size (default: 64)
   - **Learning Rate**: Optimizer learning rate (default: 0.001)
   - **Hidden Dimension**: GAT hidden dimension (default: 64)
   - **Attention Heads**: Number of attention heads (default: 4)
   - **GAT Layers**: Number of graph attention layers (default: 3)
   - **Dropout**: Dropout rate (default: 0.1)
4. Click **Start Training**
5. Monitor training metrics in the console
6. Checkpoints are saved to `checkpoints/run_<timestamp>/`

### Inference Server

1. Switch to the **Inference Server** tab
2. Click **Refresh** to load available checkpoints
3. Select a trained model checkpoint from the dropdown
4. Configure the server port (default: 5555)
5. Click **Start Server**
6. The server will be available at `127.0.0.1:5555` for Godot to connect

## Architecture

```
web_app/
├── app.py              # Flask backend with API endpoints
├── templates/
│   └── index.html      # Frontend HTML with tabs
├── static/
│   ├── style.css       # Styling
│   └── app.js          # Frontend JavaScript
├── requirements.txt    # Python dependencies
└── README.md          # This file
```

## API Endpoints

- `GET /`: Serve the main dashboard
- `GET /api/config`: Get default configuration
- `POST /api/collect/start`: Start data collection
- `POST /api/train/start`: Start training
- `POST /api/inference/start`: Start inference server
- `POST /api/process/stop/<process_id>`: Stop a running process
- `GET /api/process/status`: Get status of all processes
- `GET /api/checkpoints/list`: List available model checkpoints

## WebSocket Events

- `connect`: Client connected
- `process_output`: Real-time process output
- `process_complete`: Process finished notification

## Troubleshooting

### Port already in use
If port 5050 is already in use, modify the port in [app.py:322](app.py#L322):
```python
socketio.run(app, host='127.0.0.1', port=8080, debug=False)
```

### Godot executable not found
Update the Godot path in the Data Collection tab to match your installation path.

### No checkpoints appearing
Ensure training has completed at least once and checkpoints exist in the `checkpoints/` directory.

## Notes

- All processes run in the background and their output is streamed in real-time via WebSockets
- You can run multiple data collection sessions but only one training and one inference server at a time
- The inference server must be stopped before starting with a different checkpoint
- Console logs are displayed in real-time and can be scrolled for history
