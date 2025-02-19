# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# mainnet-beta
# server "34.230.188.212", user: "ubuntu", roles: %w{primary} #renec-mainnet1
# server "100.24.94.131", user: "ubuntu", roles: %w{primary} #renec-mainnet2
# server "34.224.180.54", user: "ubuntu", roles: %w{primary} #renec-mainnet3
# server "44.218.89.139", user: "ubuntu", roles: %w{primary} #renec-mainnet4
#
#
# server "34.229.163.107", user: "ubuntu", roles: %w{primary} #renec-mainnet1
# server "54.80.152.114", user: "ubuntu", roles: %w{primary} #renec-mainnet2
# server "3.224.210.94", user: "ubuntu", roles: %w{primary} #renec-mainnet3
# server "3.217.89.253", user: "ubuntu", roles: %w{primary} #renec-mainnet4
# server "52.206.243.123", user: "ubuntu", roles: %w{primary} #renec-mainnet5
# server "3.227.143.19", user: "ubuntu", roles: %w{primary} #renec-mainnet6
# server "34.228.32.217", user: "ubuntu", roles: %w{primary} #renec-onus
# server "18.234.202.94", user: "ubuntu", roles: %w{primary} #renec-mainnet1-new
# server "54.205.103.245", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc-bigtable
# server "3.209.79.67", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc-bigtable-backup
# server "3.219.158.133", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc3
# server "54.205.103.245", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc4
# server "125.212.234.28", user: "ubuntu", roles: %w{primary} # rpc viettel idc
# server "18.209.222.21", user: "ubuntu", roles: %w{primary} # warehouse
# server "3.82.238.67", user: "ubuntu", roles: %w{primary} # metrics
# server "18.143.240.52", user: "ubuntu", roles: %w{primary} # oracle1
# server "47.129.21.11", user: "ubuntu", roles: %w{primary} # oracle2

# testnet
# server "54.92.219.117", user: "ubuntu", roles: %w{primary} #renec-testnet
# server "54.164.58.118", user: "ubuntu", roles: %w{primary} #renec-testnet2
server "54.221.33.66", user: "ubuntu", roles: %w{primary} #renec-testnet-alter

# devnet
# server "34.233.60.216", user: "ubuntu", roles: %w{primary} #renec-devnet1
# server "3.80.214.197", user: "ubuntu", roles: %w{primary} #renec-devnet2

set :home_path, "/home/ubuntu"
set :data_full_path, "#{fetch(:home_path)}/renec-cluster"

set :renec_version, "1.14.17"
set :is_testnet, true
set :is_devnet, false

namespace :deploy do
  after :finishing, :install_all do
    on roles(:primary) do |host|
      within current_path do
        install_renec_tool_suite
        generate_keypairs
        create_renec_service(host.hostname)
        create_renec_sys_tuner_service
        restart_renec_sys_tuner
        start_renec_validator
        setup_log_rotate
        setup_prometheus
        create_node_exporter_service
        create_prometheus_service("Testnet")
      end
    end
  end
end

def setup_prometheus
  # execute "wget https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-amd64.tar.gz"
  # execute "tar xvfz prometheus-2.51.0.linux-amd64.tar.gz"
  # execute "mv prometheus-2.51.0.linux-amd64 prometheus"
  # execute "wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz"
  # execute "tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz"
  # execute "mv node_exporter-1.7.0.linux-amd64 node-exporter"
  execute "wget https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-arm64.tar.gz"
  execute "tar xvfz prometheus-2.51.0.linux-arm64.tar.gz"
  execute "mv prometheus-2.51.0.linux-arm64 prometheus"
  execute "wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-arm64.tar.gz"
  execute "tar xvfz node_exporter-1.7.0.linux-arm64.tar.gz"
  execute "mv node_exporter-1.7.0.linux-arm64 node-exporter"
end

def install_renec_tool_suite
  execute "rm -rf #{fetch(:home_path)}/.local/share/renec"
  execute "sh -c \"$(curl -sSfL https://renec-release.s3.amazonaws.com/v#{fetch(:renec_version)})\""
  execute "export PATH='#{fetch(:home_path)}/.local/share/renec/install/active_release/bin:$PATH'"

  return puts("Renec installed") if test("[ -d #{fetch(:home_path)}/.config/renec ]")
  execute "sed -i '1 i\\export PATH=\"#{fetch(:home_path)}/.local/share/renec/install/active_release/bin:$PATH\"' #{fetch(:home_path)}/.bashrc"
end

def generate_keypairs
  execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
  return puts("Keypairs existed") if test("[ -d #{fetch(:data_full_path)}/keypairs ]")

  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-identity.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-vote-account.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-stake-account.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-withdrawer.json"
end

def install_nvme
  return puts("Nvme installed") if test("[ -d #{fetch(:data_full_path)} ]")

  # ssh to server and run lsblk to get the device name
  devices = [
    "/dev/nvme1n1",
    "/dev/nvme2n1",
    "/dev/nvme3n1",
    "/dev/nvme4n1"
  ]
  label = "renec_raid"
  execute :sudo, "mdadm --create --verbose /dev/md0 --level=0 --name=#{label} --raid-devices=#{devices.size} #{devices.join(' ')}"
  execute :sudo, "mkfs.ext4 -F -L #{label} /dev/md0"
  execute :sudo, "mkfs.ext4 -F -L #{label} /dev/nvme1n1"
  execute :sudo, "mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf"
  execute :sudo, "update-initramfs -u"
  execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
  execute :sudo, "mount LABEL=#{label} #{fetch(:data_full_path)}"
  execute :sudo, "bash -c 'echo LABEL=#{label}       #{fetch(:data_full_path)}   ext4    defaults,nofail        0       2  >> /etc/fstab'"
  execute :sudo, "chown #{fetch(:username)}:#{fetch(:username)} #{fetch(:data_full_path)}"
end

# def install_storage_without_nvme
#   return puts("Storage installed") if test("[ -d #{fetch(:data_full_path)} ]")
#   execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
#   execute :sudo, "bash -c 'echo LABEL=#{label}       #{fetch(:data_full_path)}   ext4    defaults,nofail        0       2  >> /etc/fstab'"
#   execute :sudo, "chown #{fetch(:username)}:#{fetch(:username)} #{fetch(:data_full_path)}"
# end

def renec_service_definition(hostname)
  template_path = File.expand_path("../../../coin-service-conf/renec.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  start_command = start_renec_validator_command(hostname)
  start_command = start_renec_validator_command_for_testnet(hostname) if fetch(:is_testnet)
  start_command = start_renec_validator_command_for_devnet(hostname) if fetch(:is_devnet)
  namespace = OpenStruct.new(
    start_command: start_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_renec_service(hostname)
  upload! StringIO.new(renec_service_definition(hostname)), "#{current_path}/renec.service"
  execute :sudo, "cp #{current_path}/renec.service /etc/systemd/system/"
end

def start_renec_validator_command_for_testnet(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --vote-account #{fetch(:data_full_path)}/keypairs/validator-vote-account.json \
    --ledger #{fetch(:data_full_path)}/ledger \
    --tpu-coalesce-ms 50 \
    --gossip-host #{hostname} \
    --gossip-port 8001 \
    --rpc-port 8888 \
    --enable-rpc-transaction-history \
    --enable-cpi-and-log-storage \
    --dynamic-port-range 8000-8020 \
    --entrypoint 50.19.122.56:8001 \
    --expected-genesis-hash AgkLi5XY3rd2zbKDTrBbVA45fwgn3CQreeqPnGyuYqKf \
    --full-rpc-api \
    --incremental-snapshots \
    --limit-ledger-size 50000000 \
    --account-index program-id \
    --account-index spl-token-owner \
    --account-index spl-token-mint"
end

def start_renec_validator_command_for_devnet(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --vote-account #{fetch(:data_full_path)}/keypairs/validator-vote-account.json \
    --ledger #{fetch(:data_full_path)}/ledger \
    --tpu-coalesce-ms 50 \
    --gossip-host #{hostname} \
    --gossip-port 8001 \
    --rpc-port 8888 \
    --enable-rpc-transaction-history \
    --enable-cpi-and-log-storage \
    --dynamic-port-range 8000-8020 \
    --entrypoint 34.233.60.216:8001 \
    --expected-genesis-hash EKEQGSi87pCCMeuZGGA17J8vm8goNKVAANbj8kTWZ841 \
    --incremental-snapshots \
    --wait-for-supermajority 783215 --expected-shred-version 4924 --expected-bank-hash 3dMK1yxqpWBTZ9rDmHJrZtpraoHHwV8EvFyuWwV8J8JS \
    --limit-ledger-size 50000000"
    # --entrypoint 54.172.50.90:8001 \
end

def start_renec_validator_command(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --vote-account #{fetch(:data_full_path)}/keypairs/validator-vote-account.json \
    --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE \
    --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa \
    --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC \
    --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH \
    --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6 \
    --only-known-rpc \
    --ledger #{fetch(:data_full_path)}/ledger \
    --tpu-coalesce-ms 50 \
    --gossip-host #{hostname} \
    --gossip-port 8001 \
    --rpc-port 8888 \
    --enable-rpc-transaction-history \
    --enable-cpi-and-log-storage \
    --dynamic-port-range 8000-8020 \
    --entrypoint entrypoint1-mainnet-beta.renec.foundation:8001 \
    --entrypoint entrypoint2-mainnet-beta.renec.foundation:8001 \
    --entrypoint entrypoint3-mainnet-beta.renec.foundation:8001 \
    --entrypoint entrypoint4-mainnet-beta.renec.foundation:8001 \
    --entrypoint entrypoint5-mainnet-beta.renec.foundation:8001 \
    --entrypoint entrypoint6-mainnet-beta.renec.foundation:8001 \
    --expected-genesis-hash 7PNFRHLxT9FcAxSUcg3P8BraJnnUBnjuy8LwRbRJvVkX \
    --incremental-snapshots \
    --limit-ledger-size 50000000 \
    --account-index program-id  --account-index spl-token-owner  --account-index spl-token-mint \
    --enable-bigtable-ledger-upload --enable-rpc-bigtable-ledger-storage --rpc-bigtable-app-profile-id default --rpc-bigtable-instance-name solana-ledger \
    --full-rpc-api"
end

def renec_log_rotate_config
  template_path = File.expand_path("../../../coin-conf/log-rotate.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  namespace = OpenStruct.new(
    data_path: fetch(:data_full_path)
  )
  template.result(namespace.instance_eval { binding })
end

def setup_log_rotate
  upload! StringIO.new(renec_log_rotate_config), "#{current_path}/log-rotate"
  execute :sudo, "cp #{current_path}/log-rotate /etc/logrotate.d/renec"
end

def start_renec_validator
  execute :sudo, "bash -c 'cat >/etc/sysctl.d/21-solana-validator.conf <<EOF
  net.core.rmem_default = 134217728
  net.core.rmem_max = 134217728
  net.core.wmem_default = 134217728
  net.core.wmem_max = 134217728

  vm.max_map_count = 1000000

  fs.nr_open = 1000000
  EOF'"
  execute :sudo, "sysctl -p /etc/sysctl.d/21-solana-validator.conf"

  execute :sudo, "systemctl stop renec.service"
  # dangerous command
  # execute "rm -rf #{fetch(:home_path)}/renec-cluster/ledger" if fetch(:is_devnet)
  execute :sudo, "systemctl enable renec.service"
  execute :sudo, "systemctl restart renec.service"
end

def renec_sys_tuner_service_definition
  template_path = File.expand_path("../../../coin-service-conf/renec-sys-tuner.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  start_command = "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-sys-tuner --user #{fetch(:username)}"
  namespace = OpenStruct.new(
    start_command: start_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_renec_sys_tuner_service
  upload! StringIO.new(renec_sys_tuner_service_definition), "#{current_path}/renec-sys-tuner.service"
  execute :sudo, "cp #{current_path}/renec-sys-tuner.service /etc/systemd/system/"
end

def node_exporter_service_definition
  template_path = File.expand_path("../../../coin-service-conf/node-exporter.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  template.result
end

def create_node_exporter_service
  upload! StringIO.new(node_exporter_service_definition), "#{current_path}/node-exporter.service"
  execute :sudo, "cp #{current_path}/node-exporter.service /etc/systemd/system/"
  execute :sudo, "systemctl enable node-exporter.service"
  execute :sudo, "systemctl restart node-exporter.service"
end

def prometheus_service_definition
  template_path = File.expand_path("../../../coin-service-conf/prometheus.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  template.result
end

def create_prometheus_service(node_name)
  upload! StringIO.new(prometheus_config(node_name)), "#{current_path}/prometheus.yml"
  execute "cp #{current_path}/prometheus.yml /home/ubuntu/prometheus/prometheus.yml"

  upload! StringIO.new(prometheus_service_definition), "#{current_path}/prometheus.service"
  execute :sudo, "cp #{current_path}/prometheus.service /etc/systemd/system/"
  execute :sudo, "systemctl enable prometheus.service"
  execute :sudo, "systemctl restart prometheus.service"
end

def prometheus_config(job_name)
  template_path = File.expand_path("../../../coin-conf/prometheus.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  namespace = OpenStruct.new(
    job_name: job_name
  )
  template.result(namespace.instance_eval { binding })
end

def restart_renec_sys_tuner
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url mainnet-beta"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url testnet" if fetch(:is_testnet)
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url devnet" if fetch(:is_devnet)
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --keypair #{fetch(:home_path)}/renec-cluster/keypairs/validator-identity.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec address -k #{fetch(:home_path)}/renec-cluster/keypairs/validator-identity.json"
  execute :sudo, "systemctl enable renec-sys-tuner.service"
  execute :sudo, "systemctl restart renec-sys-tuner.service"
end
