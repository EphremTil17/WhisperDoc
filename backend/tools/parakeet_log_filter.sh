#!/bin/sh
set -eu

# GGML currently sends DEBUG messages through a default callback that prints
# every level. Filter only the repeated CUDA-graph warmup diagnostic while
# preserving all other native output, the server's exit status, and signals.
log_dir=$(mktemp -d /tmp/whisperdoc-parakeet-log.XXXXXX)
log_fifo="$log_dir/stream"
mkfifo "$log_fifo"

cleanup() {
    rm -f "$log_fifo"
    rmdir "$log_dir" 2>/dev/null || true
}
trap cleanup EXIT

sed -u '\|^ggml_backend_cuda_graph_compute: CUDA graph warmup complete$|d' \
    < "$log_fifo" &
filter_pid=$!

/usr/local/bin/parakeet-server "$@" > "$log_fifo" 2>&1 &
server_pid=$!

forward_signal() {
    kill -TERM "$server_pid" 2>/dev/null || true
}
trap forward_signal INT TERM

set +e
wait "$server_pid"
server_status=$?
while kill -0 "$server_pid" 2>/dev/null; do
    wait "$server_pid"
    server_status=$?
done
wait "$filter_pid"
set -e

exit "$server_status"
