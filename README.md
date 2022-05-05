# [Node exporter](https://github.com/prometheus/node_exporter) installation script

[![ci](https://github.com/carlocorradini/node_exporter_installer/actions/workflows/ci.yml/badge.svg)](https://github.com/carlocorradini/node_exporter_installer/actions/workflows/ci.yml)

:warning: Under development

:wave: Any help is appreciated

Inspired by [K3s](https://github.com/k3s-io/k3s) _install.sh_

## Usage

```shell
curl -sSfL https://raw.githubusercontent.com/carlocorradini/node_exporter_installer/main/install.sh | sh -
```

or

```shell
curl -sSfL https://raw.githubusercontent.com/carlocorradini/node_exporter_installer/main/install.sh -o install.sh
sh install.sh
```

or

```shell
curl -sSfL https://raw.githubusercontent.com/carlocorradini/node_exporter_installer/main/install.sh -o install.sh
chmod u+x
./install.sh
```

## Development

### Requirements

- [Node.js](https://nodejs.org)
- [npm](https://www.npmjs.com)

### Getting Started

1. Clone

   ```bash
   git clone https://github.com/carlocorradini/node_exporter_installer.git
   cd node_exporter_installer
   ```

1. Install Dependencies

   ```bash
   npm ci
   ```

1. Edit `install.sh`

### Check

```shell
npm run check
```

## License

This project is licensed under the [MIT](https://opensource.org/licenses/MIT) License. \
See [LICENSE](LICENSE) file for details.
