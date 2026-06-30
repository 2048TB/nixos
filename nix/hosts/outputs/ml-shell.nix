# CUDA-enabled ML dev shell, extracted from x86_64-linux/default.nix.
# Returns the `ml` devShell derivation for the given system.
{ inputs, system, mylib }:
let
  pkgsMl = import inputs.nixpkgs {
    inherit system;
    config = {
      inherit (mylib) allowUnfreePredicate;
      cudaSupport = true;
    };
  };
  mlPython = pkgsMl.python312.override {
    packageOverrides = _: prev: {
      torch = prev."torch-bin";
      pytorch = prev."pytorch-bin";
      triton = prev."triton-bin";
      openai-triton = prev."openai-triton-bin";
    };
  };
  mlCudaToolkit = pkgsMl.cudaPackages.cudatoolkit;
  mlCudnn = pkgsMl.cudaPackages.cudnn;
  mlNccl = pkgsMl.cudaPackages.nccl;
  mlPythonPackages = mlPython.pkgs;
  mlCudaLibPath = pkgsMl.lib.makeLibraryPath [
    mlCudaToolkit
    mlCudnn
    mlNccl
    pkgsMl.stdenv.cc.cc
    pkgsMl.zlib
  ];
  mlCudaRuntimeLibPath = "/run/opengl-driver/lib:/run/current-system/sw/lib:${mlCudaLibPath}";
  mlPythonEnv = mlPython.withPackages (_: with mlPythonPackages; [
    torch
    transformers
    datasets
    accelerate
    peft
    trl
    safetensors
    sentencepiece
    protobuf
    evaluate
    tensorboard
    ipykernel
    jupyterlab
  ]);
in
pkgsMl.mkShell {
  name = "nixos-ml-dev";
  packages = with pkgsMl; [
    mlPythonEnv
    uv
    git
    git-lfs
    cmake
    ninja
    pkg-config
    cudaPackages.cuda_nvcc
    mlCudaToolkit
    mlCudnn
    mlNccl
  ];
  shellHook = ''
    export CUDA_PATH="${mlCudaToolkit}"
    export CUDA_HOME="${mlCudaToolkit}"
    export CUDA_ROOT="${mlCudaToolkit}"
    export CUDNN_PATH="${mlCudnn}"
    export CUDNN_INCLUDE_DIR="${mlCudnn}/include"
    export CUDNN_LIB_DIR="${mlCudnn}/lib"
    export NCCL_ROOT_DIR="${mlNccl}"
    export NCCL_LIB_DIR="${mlNccl}/lib"
    export OPENSSL_INCLUDE_DIR="${pkgsMl.openssl.dev}/include"
    export OPENSSL_LIB_DIR="${pkgsMl.openssl.out}/lib"
    export OPENSSL_DIR="${pkgsMl.openssl.dev}"
    export LD_LIBRARY_PATH="${mlCudaRuntimeLibPath}:''${LD_LIBRARY_PATH:-}"
    export HF_HOME="''${HOME}/.cache/huggingface"
    export TRANSFORMERS_CACHE="''${HF_HOME}/hub"
    export TORCH_HOME="''${HOME}/.cache/torch"
    # 若需编译 CUDA 扩展（如 flash-attn），请根据实际显卡架构按需设置
    # export TORCH_CUDA_ARCH_LIST="8.9"
    echo "ML shell ready"
    echo "python --version"
    echo "python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'"
  '';
}
