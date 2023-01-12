# [Node exporter](https://github.com/prometheus/node_exporter) installation script

[![ci](https://github.com/carlocorradini/node_exporter_installer/actions/workflows/ci.yml/badge.svg)](https://github.com/carlocorradini/node_exporter_installer/actions/workflows/ci.yml)
[![semantic-release: angular](https://img.shields.io/badge/semantic--release-angular-e10079?logo=semantic-release)](https://github.com/semantic-release/semantic-release)

Inspired by [K3s](https://github.com/k3s-io/k3s) `install.sh`

## Usage

```sh
curl -sSfL https://raw.githubusercontent.com/carlocorradini/node_exporter_installer/main/install.sh | sh -
```

### Uninstall

```sh
$INSTALL_NODE_EXPORTER_BIN_DIR/node_exporter.uninstall.sh
```

## Example

### Enable only os collector

> **Note**: The following commands result in the same behavior

```sh
curl ... | INSTALL_NODE_EXPORTER_EXEC="--collector.disable-defaults --collector.os" sh -s -
```

```sh
curl ... | INSTALL_NODE_EXPORTER_EXEC="--collector.disable-defaults" sh -s - --collector.os
```

```sh
curl ... | sh -s - --collector.disable-defaults --collector.os
```

### Download a specific version without starting the service

```sh
curl ... | INSTALL_NODE_EXPORTER_VERSION="v1.5.0" INSTALL_NODE_EXPORTER_SKIP_START="true" sh -
```

## Environment variables

| **Name**                              | **Description**                                                                                         | **Default**                    |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `INSTALL_NODE_EXPORTER_SKIP_DOWNLOAD` | Skip downloading Node exporter. There must already be an executable binary at `<BIN_DIR>/node_exporter` | `false`                        |
| `INSTALL_NODE_EXPORTER_FORCE_RESTART` | Force restarting Node exporter service                                                                  | `false`                        |
| `INSTALL_NODE_EXPORTER_SKIP_ENABLE`   | Skip enabling Node exporter service at startup                                                          | `false`                        |
| `INSTALL_NODE_EXPORTER_SKIP_START`    | Skip starting Node exporter service                                                                     | `false`                        |
| `INSTALL_NODE_EXPORTER_SKIP_FIREWALL` | Skip firewall rules. Supported firewalls are `firewall-cmd`, `ufw` and `iptables`                       | `false`                        |
| `INSTALL_NODE_EXPORTER_SKIP_SELINUX`  | Skip changing `SELinux` context for Node exporter binary                                                | `false`                        |
| `INSTALL_NODE_EXPORTER_VERSION`       | Version of Node exporter to download                                                                    | `latest`                       |
| `INSTALL_NODE_EXPORTER_BIN_DIR`       | Directory to install Node exporter binary and uninstall script                                          | `/usr/local/bin` or `/opt/bin` |
| `INSTALL_NODE_EXPORTER_SYSTEMD_DIR`   | Directory to install systemd service files                                                              | `/etc/systemd/system`          |
| `INSTALL_NODE_EXPORTER_EXEC`          | Node exporter arguments                                                                                 |

## Contributing

I would love to see your contribution :heart:

See [CONTRIBUTING](./CONTRIBUTING.md) guidelines.

## License

This project is licensed under the [MIT](https://opensource.org/licenses/MIT) License. \
See [LICENSE](./LICENSE) file for details.
