# Todo

This file is about to taking notes for todos

## 1. High Priorities

High priority todos

*   **example1:** `1. examples`
*   **example2:** `2. example of '$HOME/some_dir\some.sh'`

## 2. Getting Help

If you're ever unsure what to do, you can ask for help:

```
/help
```

## 3. Notes & Tests

## Portainer (?)
docker run -d -p 9000:9000 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest

## Pinokio install Notes



``` pytorch for me
conda create -n pytorch_env python=3.11
conda activate pytorch_env

conda install pytorch torchvision torchaudio pytorch-cuda=12.1 -c pytorch -c nvidia

python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
```

wget https://github.com/pinokiocomputer/pinokio/releases/download/3.9.0/Pinokio_3.9.0_amd64.deb

>> rust desk ile bağlan
conda activate pytorch_env
sudo dpkg -i Pinokio_3.9.0_amd64.deb
$ pinokio

``` condarc
channels:
  - pytorch
  - nvidia
  - conda-forge
  - defaults
channel_priority: strict
envs_dirs:
  - /home/kyilmaz/miniconda3/envs
auto_activate_base: false
pip_interop_enabled: true

# PyTorch and CUDA
create_default_packages:
  - python=3.11
  - cudatoolkit=12.1
  - numpy
envs_dirs:
  - /home/kyilmaz/miniconda3/envs
pkgs_dirs:
  - /home/kyilmaz/miniconda3/pkgs
remote_connect_timeout_secs: 20.0
remote_read_timeout_secs: 300.0
remote_max_retries: 6
report_errors: false
 ```
 
 ``` pipconfig
[global]
  timeout = 1000
  index-url = https://download.pytorch.org/whl/cu121
  extra-index-url = https://pypi.org/simple
  trusted-host =
    download.pytorch.org
    pypi.org
    files.pythonhosted.org

[install]
  no-cache-dir = false
  prefer-binary = true  
```

echo "conda activate pytorch_env 2> /dev/null || true" >> ~/.profile


---> 
conda_env is /home/kyilmaz/miniconda3/

cd /home/kyilmaz/pinokio

cat ENVIRONMENT >>

gitconfig
pipconfig
condarc

dosyaları var

>>

(ok)


conda activate pytorch_env


# 3. Eksik bağımlılıkları tamamla
sudo apt-get install -f

# 4. Gerekirse CUDA, Python, Node.js, nvidia sürücüleri kur
# 5. Pinokio'yu başlat
pinokio
