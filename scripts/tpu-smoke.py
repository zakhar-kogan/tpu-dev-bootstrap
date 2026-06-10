import torch
import torch_xla.core.xla_model as xm
import jax


def main() -> None:
    # PyTorch/XLA smoke test
    device = xm.xla_device()
    x = torch.ones((2, 2), device=device)
    y = x @ x
    print(f"PyTorch device={device}")
    print(f"PyTorch result:\n{y.cpu()}")

    # JAX smoke test
    print(f"JAX devices: {jax.devices()}")
    a = jax.numpy.ones((2, 2))
    b = a @ a
    print(f"JAX result:\n{b}")


if __name__ == "__main__":
    main()

