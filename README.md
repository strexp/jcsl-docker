# jcsl-docker

Oracle Java Card Development Kit Simulator 3.2 (`jcsl`) in a Debian slim
container.

`jcsl` is a 32-bit i386 glibc binary, so the image is `linux/amd64` only and
uses `libc6-i386`. OpenJDK 21 headless runs the key configurator at startup.

## Build

```sh
docker build --platform linux/amd64 \
  --build-arg JCSL_ACCEPT_LICENSE=yes \
  -t jcsl-docker .
```

`JCSL_ACCEPT_LICENSE=yes` is required at build time. The download uses the
Oracle OTN cookie `oraclelicense=accept-securebackup-cookie`. To use a mirror
or a pre-downloaded archive:

```sh
docker build --platform linux/amd64 \
  --build-arg JCSL_ACCEPT_LICENSE=yes \
  --build-arg JCSL_URL=https://example.internal/jcsl.tar.gz \
  -t jcsl-docker .
```

## Run

The included [`compose.yaml`](compose.yaml) is a runnable example:

```sh
docker compose up --build
```

Or run it directly:

```sh
docker run --rm -it --platform linux/amd64 \
  -e JCSL_ACCEPT_LICENSE=yes \
  -e JCSL_BIND_IP=0.0.0.0 \
  -e JCSL_PORT=9025 \
  -e JCSL_KVN=01 \
  -e JCSL_ENC_KEY=11111111111111111111111111111111 \
  -e JCSL_MAC_KEY=22222222222222222222222222222222 \
  -e JCSL_DEK_KEY=33333333333333333333333333333333 \
  -e JCSL_GLOBAL_PIN=000000000000 \
  -e JCSL_PIN_TRIES=03 \
  -p 9025:9025 \
  jcsl-docker
```

Verify with GlobalPlatformPro:

```sh
java -jar gp.jar --ng --simulator 127.0.0.1:9025 \
  --key-enc 11111111111111111111111111111111 \
  --key-mac 22222222222222222222222222222222 \
  --key-dek 33333333333333333333333333333333 \
  --key-ver 01 -l
```

The same `JCSL_ACCEPT_LICENSE=yes` must be passed at runtime; it is not baked
into the image.

## Environment variables

| Variable | Stage | Default | Description |
|---|---|---|---|
| `JCSL_ACCEPT_LICENSE` | build + run | required | Must be `yes` |
| `JCSL_URL` | build | Oracle URL | Override the simulator archive URL |
| `JCSL_KVN` | run | `01` | SCP03 key version (1 byte hex) |
| `JCSL_ENC_KEY` | run | `404142434445464748494A4B4C4D4E4F` | ENC key (16/24/32 bytes hex) |
| `JCSL_MAC_KEY` | run | `404142434445464748494A4B4C4D4E4F` | MAC key (same length as ENC) |
| `JCSL_DEK_KEY` | run | `404142434445464748494A4B4C4D4E4F` | DEK key (same length as ENC) |
| `JCSL_GLOBAL_PIN` | run | `000000000000` | Global PIN (3–16 bytes hex) |
| `JCSL_PIN_TRIES` | run | `03` | PIN retry count (1 byte hex) |
| `JCSL_BIND_IP` | run | `0.0.0.0` | Address to listen on |
| `JCSL_PORT` | run | `9025` | Port to listen on |
| `JCSL_INTERNAL_PORT` | run | auto | Internal jcsl port; rarely needed |

Values are hex-encoded bytes, not raw strings. For example,
`313233343536` is the ASCII PIN `"123456"`, and `000000000000` is `"000000"`.
The defaults are test keys and should be replaced in real use.

## Notes

- `jcsl` only accepts `-p=<port>` and always binds `0.0.0.0`. The container
  runs it on an internal port and uses `socat` to listen on
  `JCSL_BIND_IP:JCSL_PORT`. To bind to `127.0.0.1`, use host networking
  (`--network=host` / `network_mode: host`); when publishing ports, keep the
  default `0.0.0.0`.
- The internal port is auto-selected; set `JCSL_INTERNAL_PORT` to pin it.
- The container runs as uid `10001`. For a read-only root filesystem, provide
  writable tmpfs at `/var/lib/jcsl` and `/tmp`, for example
  `--read-only --tmpfs /var/lib/jcsl:mode=1777 --tmpfs /tmp`.
- Only `linux/amd64` is supported.
