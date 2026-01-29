"""
GAT Inference Server for Godot.

Loads a trained ActionGAT model and serves predictions over a TCP socket.
Godot connects as a client and sends JSON requests, receives JSON responses.

Usage:
    python inference_server.py <checkpoint_dir> [--port 5555]

Protocol (TCP, newline-delimited JSON):
    Request:  {"node_features": [[4,11]], "edge_index": [[src],[dst]], "edge_attr": [[n,6]], "agent_idx": int, "legal_mask": [10]}
    Response: {"action_id": int, "confidence": float, "action_probs": [10]}
"""

import sys
import json
import os
import socket
import argparse

import torch
import torch.nn.functional as F
from torch_geometric.data import Data

from gat_model import ActionGAT


def load_model(checkpoint_dir: str, device: torch.device) -> ActionGAT:
    """Load a trained model from a checkpoint directory."""
    config_path = os.path.join(checkpoint_dir, "config.json")
    model_path = os.path.join(checkpoint_dir, "best_model.pt")

    if not os.path.exists(model_path):
        model_path = os.path.join(checkpoint_dir, "final_model.pt")

    with open(config_path, "r") as f:
        config = json.load(f)

    meta = config.get("dataset_meta", {})
    model = ActionGAT(
        node_features=meta.get("node_feature_dim", 11),
        edge_features=meta.get("edge_feature_dim", 6),
        hidden_dim=config.get("hidden_dim", 64),
        num_heads=config.get("num_heads", 4),
        num_layers=config.get("num_layers", 3),
        num_actions=meta.get("num_actions", 10),
        dropout=0.0,
    )

    checkpoint = torch.load(model_path, map_location=device, weights_only=False)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.to(device)
    model.eval()

    return model


def build_graph_data(request: dict, device: torch.device) -> Data:
    """Convert a JSON request to a PyTorch Geometric Data object."""
    x = torch.tensor(request["node_features"], dtype=torch.float32)
    edge_index = torch.tensor(request["edge_index"], dtype=torch.long)
    edge_attr = torch.tensor(request["edge_attr"], dtype=torch.float32)

    if edge_index.numel() == 0:
        edge_index = torch.zeros((2, 0), dtype=torch.long)
        edge_attr = torch.zeros((0, 6), dtype=torch.float32)

    agent_idx = torch.tensor([request["agent_idx"]], dtype=torch.long)
    legal_mask = torch.tensor([request["legal_mask"]], dtype=torch.float32)
    batch = torch.zeros(x.size(0), dtype=torch.long)

    data = Data(x=x, edge_index=edge_index, edge_attr=edge_attr)
    data.batch = batch
    data.agent_idx = agent_idx
    data.legal_mask = legal_mask

    return data.to(device)


@torch.no_grad()
def predict(model: ActionGAT, data: Data) -> dict:
    """Run inference and return action prediction."""
    logits = model.predict_with_mask(
        data.x, data.edge_index, data.edge_attr,
        data.batch, data.agent_idx, data.legal_mask
    )

    probs = F.softmax(logits, dim=1).squeeze(0)
    action_id = probs.argmax().item()
    confidence = probs[action_id].item()

    return {
        "action_id": action_id,
        "confidence": round(confidence, 4),
        "action_probs": [round(p, 4) for p in probs.tolist()]
    }


def serve(model, device, port):
    """Run TCP server that handles one connection at a time."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(1)
    print(f"Inference server listening on 127.0.0.1:{port}")

    while True:
        conn, addr = server.accept()
        print(f"Client connected: {addr}")
        buf = ""

        try:
            while True:
                data = conn.recv(4096)
                if not data:
                    break

                buf += data.decode("utf-8")

                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        request = json.loads(line)
                        graph_data = build_graph_data(request, device)
                        result = predict(model, graph_data)
                        response = json.dumps(result) + "\n"
                        conn.sendall(response.encode("utf-8"))
                    except Exception as e:
                        error_resp = json.dumps({"error": str(e)}) + "\n"
                        conn.sendall(error_resp.encode("utf-8"))

        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            conn.close()
            print(f"Client disconnected: {addr}")


def main():
    parser = argparse.ArgumentParser(description="GAT Inference Server")
    parser.add_argument("checkpoint_dir", help="Path to checkpoint directory")
    parser.add_argument("--port", type=int, default=5555, help="TCP port (default: 5555)")
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    print(f"Loading model from {args.checkpoint_dir}...")
    model = load_model(args.checkpoint_dir, device)
    num_params = sum(p.numel() for p in model.parameters())
    print(f"Model loaded: {num_params:,} parameters on {device}")

    serve(model, device, args.port)


if __name__ == "__main__":
    main()
