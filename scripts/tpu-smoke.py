import torch
import torch_xla.core.xla_model as xm


def main() -> None:
    device = xm.xla_device()
    x = torch.ones((2, 2), device=device)
    y = x @ x
    print(f"device={device}")
    print(y.cpu())


if __name__ == "__main__":
    main()
