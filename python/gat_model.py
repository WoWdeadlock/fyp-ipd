"""
Graph Attention Network for Action Prediction

A GAT model that predicts optimal actions for each agent
based on the game state represented as a graph.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch_geometric.nn import GATConv, global_mean_pool
from torch_geometric.data import Data, Batch


class ActionGAT(nn.Module):
    """
    Graph Attention Network for multi-agent action prediction.

    Architecture:
        1. Node embedding layer
        2. Multiple GAT layers with attention
        3. Agent-specific action heads

    Input:
        - Node features: [batch_size * 4, 11]
        - Edge index: [2, num_edges]
        - Edge attr: [num_edges, 6]
        - Agent index: which agent to predict for

    Output:
        - Action logits: [batch_size, 10] (one for each action)
    """

    def __init__(
        self,
        node_features: int = 11,
        edge_features: int = 6,
        hidden_dim: int = 64,
        num_heads: int = 4,
        num_layers: int = 3,
        num_actions: int = 10,
        dropout: float = 0.1
    ):
        super().__init__()

        self.node_features = node_features
        self.hidden_dim = hidden_dim
        self.num_actions = num_actions

        # Node embedding
        self.node_embed = nn.Linear(node_features, hidden_dim)

        # Edge embedding
        self.edge_embed = nn.Linear(edge_features, hidden_dim)

        # GAT layers
        self.gat_layers = nn.ModuleList()
        self.gat_layers.append(
            GATConv(hidden_dim, hidden_dim // num_heads, heads=num_heads,
                    edge_dim=hidden_dim, dropout=dropout)
        )
        for _ in range(num_layers - 1):
            self.gat_layers.append(
                GATConv(hidden_dim, hidden_dim // num_heads, heads=num_heads,
                        edge_dim=hidden_dim, dropout=dropout)
            )

        # Layer norms
        self.layer_norms = nn.ModuleList([
            nn.LayerNorm(hidden_dim) for _ in range(num_layers)
        ])

        # Agent-specific action heads
        # Tank: actions 0-3 (wait, melee, taunt, defensive)
        # Healer: actions 0, 4-6 (wait, heal, shield, restore)
        # Sniper: actions 0, 7-9 (wait, shot, cripple, power)
        self.action_head = nn.Sequential(
            nn.Linear(hidden_dim * 2, hidden_dim),  # Agent node + global context
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, num_actions)
        )

        self.dropout = nn.Dropout(dropout)

    def forward(
        self,
        x: torch.Tensor,
        edge_index: torch.Tensor,
        edge_attr: torch.Tensor,
        batch: torch.Tensor,
        agent_idx: torch.Tensor
    ) -> torch.Tensor:
        """
        Forward pass.

        Args:
            x: Node features [num_nodes, 11]
            edge_index: Edge connectivity [2, num_edges]
            edge_attr: Edge features [num_edges, 6]
            batch: Batch assignment [num_nodes]
            agent_idx: Agent index for each graph [batch_size]

        Returns:
            Action logits [batch_size, 10]
        """
        # Embed nodes and edges
        h = self.node_embed(x)
        e = self.edge_embed(edge_attr) if edge_attr.size(0) > 0 else None

        # GAT layers with residual connections
        for i, gat in enumerate(self.gat_layers):
            h_new = gat(h, edge_index, edge_attr=e)
            h_new = self.layer_norms[i](h_new)
            h = h + self.dropout(F.elu(h_new))  # Residual

        # Get agent node features for each graph in batch
        # Each graph has 4 nodes, agent_idx tells us which one
        batch_size = agent_idx.size(0)
        agent_features = []

        for i in range(batch_size):
            # Find nodes belonging to this graph
            graph_mask = (batch == i)
            graph_nodes = h[graph_mask]  # [4, hidden_dim]

            # Get the specific agent's features
            agent_feat = graph_nodes[agent_idx[i]]  # [hidden_dim]
            agent_features.append(agent_feat)

        agent_features = torch.stack(agent_features)  # [batch_size, hidden_dim]

        # Global context via mean pooling
        global_context = global_mean_pool(h, batch)  # [batch_size, hidden_dim]

        # Combine agent features with global context
        combined = torch.cat([agent_features, global_context], dim=1)  # [batch_size, hidden_dim*2]

        # Action prediction
        logits = self.action_head(combined)  # [batch_size, num_actions]

        return logits

    def predict_with_mask(
        self,
        x: torch.Tensor,
        edge_index: torch.Tensor,
        edge_attr: torch.Tensor,
        batch: torch.Tensor,
        agent_idx: torch.Tensor,
        legal_mask: torch.Tensor
    ) -> torch.Tensor:
        """
        Predict with legal action masking.
        Illegal actions get -inf logits.
        """
        logits = self.forward(x, edge_index, edge_attr, batch, agent_idx)

        # Reshape legal_mask if batched as flat 1D by PyG
        if legal_mask.dim() == 1 and logits.dim() == 2:
            legal_mask = legal_mask.view(logits.size(0), -1)

        # Mask illegal actions
        mask = (legal_mask == 0)
        logits = logits.masked_fill(mask, float('-inf'))

        return logits


class SimpleMLP(nn.Module):
    """
    Simple MLP baseline using flat features.
    Use this for comparison with GAT.
    """

    def __init__(
        self,
        input_dim: int = 32,  # Flat feature size
        hidden_dim: int = 128,
        num_actions: int = 10,
        dropout: float = 0.1
    ):
        super().__init__()

        self.mlp = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, num_actions)
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.mlp(x)


def train_epoch(model, loader, optimizer, device):
    """Train for one epoch."""
    model.train()
    total_loss = 0
    correct = 0
    total = 0

    for batch in loader:
        batch = batch.to(device)
        optimizer.zero_grad()

        # Forward pass
        logits = model.predict_with_mask(
            batch.x, batch.edge_index, batch.edge_attr,
            batch.batch, batch.agent_idx, batch.legal_mask
        )

        # Loss
        loss = F.cross_entropy(logits, batch.y)
        loss.backward()
        optimizer.step()

        total_loss += loss.item()

        # Accuracy
        pred = logits.argmax(dim=1)
        correct += (pred == batch.y).sum().item()
        total += batch.y.size(0)

    return total_loss / len(loader), correct / total


@torch.no_grad()
def evaluate(model, loader, device):
    """Evaluate on a dataset."""
    model.eval()
    total_loss = 0
    correct = 0
    total = 0

    for batch in loader:
        batch = batch.to(device)

        logits = model.predict_with_mask(
            batch.x, batch.edge_index, batch.edge_attr,
            batch.batch, batch.agent_idx, batch.legal_mask
        )

        loss = F.cross_entropy(logits, batch.y)
        total_loss += loss.item()

        pred = logits.argmax(dim=1)
        correct += (pred == batch.y).sum().item()
        total += batch.y.size(0)

    return total_loss / len(loader), correct / total


# Example training script
if __name__ == "__main__":
    import sys
    from torch_geometric.loader import DataLoader
    from gat_dataset import MCTSDataset

    if len(sys.argv) < 2:
        print("Usage: python gat_model.py <data_dir>")
        sys.exit(1)

    data_dir = sys.argv[1]
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    # Load dataset
    print("Loading dataset...")
    dataset = MCTSDataset(data_dir)
    print(f"Dataset size: {len(dataset)}")

    # Split into train/val
    train_size = int(0.8 * len(dataset))
    val_size = len(dataset) - train_size
    train_dataset, val_dataset = torch.utils.data.random_split(
        dataset, [train_size, val_size]
    )

    train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=64)

    # Create model
    model = ActionGAT(
        node_features=11,
        edge_features=6,
        hidden_dim=64,
        num_heads=4,
        num_layers=3,
        num_actions=10
    ).to(device)

    print(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")

    # Optimizer
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode='max', factor=0.5, patience=5
    )

    # Training loop
    best_val_acc = 0
    for epoch in range(100):
        train_loss, train_acc = train_epoch(model, train_loader, optimizer, device)
        val_loss, val_acc = evaluate(model, val_loader, device)

        scheduler.step(val_acc)

        print(f"Epoch {epoch+1:3d} | "
              f"Train Loss: {train_loss:.4f} Acc: {train_acc:.3f} | "
              f"Val Loss: {val_loss:.4f} Acc: {val_acc:.3f}")

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), "best_model.pt")
            print(f"  -> Saved best model (val_acc: {val_acc:.3f})")

    print(f"\nBest validation accuracy: {best_val_acc:.3f}")
