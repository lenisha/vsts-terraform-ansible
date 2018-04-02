#!/bin/bash
ls -la
echo "************* execute terraform graph"
## execute terrafotm build and sendout to packer-build-output

terraform graph | dot -Tsvg > graph.svg