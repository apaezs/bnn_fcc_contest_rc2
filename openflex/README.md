# Openflex 

The openflex tool to collect timing and area results, in addition to performing the final verification tests for the contest.


## Collecting Timing and Area Results

Openflex uses a YAML file to specify the details of the project. Dr. Stitt provided the [bnn_fcc_timing.yml YAML file](bnn_fcc_timing.yml) for collecting timing and area results which we modified to specify all of our source files.

For out-of-context timing analysis, it is usually a good idea to ensure that the I/O is registered. Dr. Stitt provided this for us in [rtl/bnn_fcc_timing.sv](rtl/bnn_fcc_timing.sv), which will be the top-level module for synthesis when collecting results.


Run openflex to collecting timing results with the following:

```bash
openflex bnn_fcc_timing.yml -c bnn_fcc.csv
```

This command will create a Vivado project, execute Vivado to synthesize, place, and route your design, and will then report maximum clock frequency and area numbers in bnn_fcc.csv.
You can see an example in [example.csv](example.csv).

If you get errors when running openflex here, make sure that Vivado is in your PATH, that the YAML file contains all required source files, and that openflex is activated.

## Verification

For verifying your final design, update the [bnn_fcc_verification.yml](bnn_fcc_verification.yml) file with your design sources like before. You do not need bnn_fcc_timing.sv here.

Design can be verified like this:

```bash
openflex bnn_fcc_verify.yml
```

```bash
openflex bnn_fcc_coverage_verify.yml
```

But, this requires you to manually scan the output and verify correctness. I've automated that with the simple bash script [verify.sh](verify.sh). To run it, simply do:

```bash
./verify.sh
```

If it doesn't run, first try:

```bash
chmod +x verify.sh
```

If your simulation is successful, it will report:

```bash
Verification PASSED
```

If your simulation fails, it will report:

```bash
Verification FAILED (see run.log)
```

where run.log contains the output from the simulation.






