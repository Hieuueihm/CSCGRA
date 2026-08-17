# Reference models

Reference and golden-model implementations live here. RTL test vectors that
are compiled directly by a testbench live under the corresponding
`verification/v1` or `verification/v2` directory.

Models are not synthesizable source and are not automatically compiled by the
canonical RTL flow. Treat frozen golden inputs as independent correctness
references; do not modify them to accommodate an RTL regression.
