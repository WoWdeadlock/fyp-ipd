"""
Quick training script for the GAT action predictor.

Usage:
    python train.py <data_dir> [--epochs 100] [--batch-size 64]

Example:
    python train.py "C:/Users/User/AppData/Roaming/Godot/app_userdata/IPD/training_data"
"""

import argparse
import os
import json
from datetime import datetime

import torch
import torch.nn.functional as F
from torch_geometric.loader import DataLoader

from gat_dataset import MCTSDataset, load_metadata, get_action_name
from gat_model import ActionGAT, train_epoch, evaluate


def main():
    parser = argparse.ArgumentParser(description="Train GAT action predictor")
    parser.add_argument("data_dir", help="Path to training data directory")
    parser.add_argument("--epochs", type=int, default=100, help="Number of epochs")
    parser.add_argument("--batch-size", type=int, default=64, help="Batch size")
    parser.add_argument("--lr", type=float, default=0.001, help="Learning rate")
    parser.add_argument("--hidden-dim", type=int, default=64, help="Hidden dimension")
    parser.add_argument("--num-heads", type=int, default=4, help="Number of attention heads")
    parser.add_argument("--num-layers", type=int, default=3, help="Number of GAT layers")
    parser.add_argument("--dropout", type=float, default=0.1, help="Dropout rate")
    parser.add_argument("--output-dir", type=str, default="./checkpoints", help="Output directory")
    args = parser.parse_args()

    # Device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    # Load dataset
    print(f"\nLoading dataset from: {args.data_dir}")
    meta = load_metadata(args.data_dir)
    print(f"  Episodes: {meta.get('total_episodes', 'N/A')}")
    print(f"  Samples: {meta.get('total_samples', 'N/A')}")
    print(f"  Win rate: {meta.get('win_rate', 0) * 100:.1f}%")

    dataset = MCTSDataset(args.data_dir)
    print(f"  Loaded: {len(dataset)} samples")

    # Split
    train_size = int(0.8 * len(dataset))
    val_size = len(dataset) - train_size
    train_dataset, val_dataset = torch.utils.data.random_split(
        dataset, [train_size, val_size],
        generator=torch.Generator().manual_seed(42)
    )
    print(f"  Train: {len(train_dataset)}, Val: {len(val_dataset)}")

    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=args.batch_size)

    # Model
    model = ActionGAT(
        node_features=meta.get("node_feature_dim", 11),
        edge_features=meta.get("edge_feature_dim", 6),
        hidden_dim=args.hidden_dim,
        num_heads=args.num_heads,
        num_layers=args.num_layers,
        num_actions=meta.get("num_actions", 10),
        dropout=args.dropout
    ).to(device)

    num_params = sum(p.numel() for p in model.parameters())
    print(f"\nModel: {num_params:,} parameters")

    # Optimizer
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.01)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)

    # Output directory
    os.makedirs(args.output_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = os.path.join(args.output_dir, f"run_{timestamp}")
    os.makedirs(run_dir, exist_ok=True)

    # Save config
    config = vars(args)
    config["device"] = str(device)
    config["num_params"] = num_params
    config["dataset_meta"] = meta
    with open(os.path.join(run_dir, "config.json"), "w") as f:
        json.dump(config, f, indent=2)

    # Training loop
    print(f"\n{'='*60}")
    print("TRAINING")
    print(f"{'='*60}")

    best_val_acc = 0
    history = []

    for epoch in range(args.epochs):
        train_loss, train_acc = train_epoch(model, train_loader, optimizer, device)
        val_loss, val_acc = evaluate(model, val_loader, device)
        scheduler.step()

        lr = optimizer.param_groups[0]['lr']

        history.append({
            "epoch": epoch + 1,
            "train_loss": train_loss,
            "train_acc": train_acc,
            "val_loss": val_loss,
            "val_acc": val_acc,
            "lr": lr
        })

        print(f"Epoch {epoch+1:3d}/{args.epochs} | "
              f"Train: {train_loss:.4f} ({train_acc:.1%}) | "
              f"Val: {val_loss:.4f} ({val_acc:.1%}) | "
              f"LR: {lr:.6f}")

        # Save best model
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save({
                "epoch": epoch + 1,
                "model_state_dict": model.state_dict(),
                "optimizer_state_dict": optimizer.state_dict(),
                "val_acc": val_acc,
                "config": config
            }, os.path.join(run_dir, "best_model.pt"))
            print(f"  -> Saved best model (val_acc: {val_acc:.1%})")

        # Save history
        with open(os.path.join(run_dir, "history.json"), "w") as f:
            json.dump(history, f, indent=2)

    # Final save
    torch.save({
        "epoch": args.epochs,
        "model_state_dict": model.state_dict(),
        "optimizer_state_dict": optimizer.state_dict(),
        "val_acc": val_acc,
        "config": config
    }, os.path.join(run_dir, "final_model.pt"))

    print(f"\n{'='*60}")
    print("TRAINING COMPLETE")
    print(f"{'='*60}")
    print(f"Best validation accuracy: {best_val_acc:.1%}")
    print(f"Checkpoints saved to: {run_dir}")


if __name__ == "__main__":
    main()
