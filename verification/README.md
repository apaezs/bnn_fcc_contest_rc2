# Binary Neural Net (BNN) Fully Connected Classifier (FCC) Testbench (bnn_fcc_tb)

This folder contains the parameterized SystemVerilog testbench for verifying the fully connected binary neural network classifier provided by Dr. Stitt. It supports both a fixed SFC topology (784-256-256-10) for MNIST digit recognition and user-defined custom topologies.

It also contains our expanded testbench to reach more coverage across edge cases with directed tests.

## Features (Provided Testbench)
* **Dual Mode Operation**: Toggle between trained MNIST weights or randomized models for architectural exploration.
* **AXI4-Stream Integration**: Fully compliant handshaking with configurable bus widths and randomized back-pressure/validity.
* **Automated Reference Model**: Includes a SystemVerilog-based reference model to verify hardware outputs against expected Python-generated results.
* **Parameterized Parallelism**: Configurable neuron and input parallelism to match your specific DUT implementation.
* **Benchmarking**: Tracks latency and throughput.

---

## Getting Started

### Prerequisites
* **Simulator**: Siemens Questa/ModelSim (recommended) or any IEEE 1800-2012 compliant simulator.
* **Data Files**: Ensure the Python model data and test vectors are located in the directory specified by `BASE_DIR`.


### Running the Simulation

Before running, make sure Vivado is added to shell enviornment/source path and openflex is installed either in a Python virtual enviornment or system-wide.
#### CLI Mode (Provided TB)

```bash
cd ../openflex
openflex bnn_fcc_verify.yml
```

#### CLI Mode (Custom TB)

```bash
cd ../openflex
openflex bnn_fcc_coverage_verify.yml
```

## Expanded Coverage

For all of the coverage groups defined below except `cg_data_in_inter_image_gap`, we achieved 100 percent coverage on the defined bins using directed tests and the existing tests from the provided testbench. If we had more time, we would have implemented more directed tests based on the coverage plan. This is all checked in `bnn_fcc_coverage_tb.sv`.

### Configuration Bus
To verify the config bus worked correctly under different conditions, we set up coverage across many cases:

* Both full-width and partial `tkeep` values occurring
* Beats arriving both continuously and after a gap
* Configuring the system in all orders (`weights -> weights`, `weights -> thresholds`, `thresholds -> weights`, `thresholds -> thresholds`)
* Reserved header fields fed with non-zero values
* Stall cycles accumulated in a burst from 0 to 200
* Stalls occurring on header and payload beats
* Gaps between two config messages from 0 to 500 cycles
* Single- and multi-beat messages for both message types

### Data Bus
* Various ranges of bursts or consecutive beats without gaps from 0 to 513
* Gap lengths before a beat from 0 to 500
* Gap lengths occurring on the last beat of an image
* Pixel content with all zeros, all ones, and mixed values
* Full and partial `tkeep` occurring during tests
* Idle gaps between images from 0 to 1000 cycles

### Output Bus
* Backpressure present before each output is accepted
* Backpressure durations from 0 to 1000 cycles
* All classes predicted by the DUT
* Backpressure occurring at the exact output handshake

### Input Diversity
* Uniform images with all pixels identical
* Low-spread images
* High-spread images

### Scenarios
* Reset occurring during idle, in the middle of configuration, in the middle of inputs, and in the middle of output
* Reset interrupting partial config
* Only weights and thresholds sent before reset
* Reset when `tlast` is asserted on the config bus

## Testbench Parameters

The testbench is highly configurable via SystemVerilog parameters. They are grouped into the following categories:

### Configuration
| Parameter | Description |
| :--- | :--- |
| `USE_CUSTOM_TOPOLOGY` | `0`: Use MNIST SFC (784->256->256->10). `1`: Use `CUSTOM_TOPOLOGY` array. |
| `CUSTOM_LAYERS` | The number of layers (input, hidden, and output) in the custom topolgoy. |
| `CUSTOM_TOPOLOGY` | Array specifying all layers. 0: number of inputs, 1 to CUSTOM_LAYERS-1: number of neurons in layer. |
| `NUM_TEST_IMAGES` | Total images to stream during simulation. |
| `VERIFY_MODEL` | Cross-check SV results against Python model (only applicable to USE_CUSTOM_TOPOLOGY=1'b0) |
| `BASE_DIR` |  Path to Python model data and test vectors (must be set relative to your simulator's working directory) |
| `TOGGLE_DATA_OUT_READY`| Randomly toggles data_out_ready to simulate back-pressure. Must be enabled to fully pass tests for contest. Disable to measure throughput and latency. |
| `CONFIG_VALID_PROBABILITY` |  Real value from 0.0 to 1.0 that specifies the probability of the configuration bus providing valid data while the DUT is ready. Used to simulate a slow upstream producer. Must be set to a value less than 1.0 to full pass testing, but should be set to 1 to measure performance. |
| `DATA_IN_VALID_PROBABILITY` | Real value from 0.0 to 1.0 that specifies the probability of the data_in bus providing valid pixels while the DUT is ready. Used to simulate a slow upstream producer. Must be set to a value less than 1.0 to fully pass testing, but should be set to 1 to measure performance. |
| `TIMEOUT` | Realtime value that specifies the maximum amount of time the testbench is allowed to run before being terminated. Adjust based on the expected performance of your design. |
| `CLK_PERIOD` | Realtime value specifying the clock period. Set based on Vivado fmax to get correct latency and throughput stats. |
| `DEBUG` | Set to print model details and an inference trace for each layer. |

### Bus Configuration
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `CONFIG_BUS_WIDTH` | `64` | Bit-width for the AXI-Stream configuration bus. |
| `INPUT_BUS_WIDTH` | `64` | Bit-width for the AXI-Stream input pixel bus. |
| `OUTPUT_BUS_WIDTH` | `8` | Bit-width for the AXI-Stream inference output bus. |

The bus widths were not changed in our design even though we reached enough throughput where the INPUT_BUS_WIDTH becAME the bottleneck.

### App Configuration

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `INPUT_DATA_WIDTH` | `8` | **Fixed at 8**. Bit-width of individual pixels. |
| `OUTPUT_DATA_WIDTH` | `4` | **Fixed at 4**. Bit-width of inference output. |

These were not changed for the contest. The code is untested for other widths.

### DUT Configuration

| Parameter | Description |
| :--- | :--- |
| `PARALLEL_INPUTS` | Number of inputs/weights processed in parallel in the first hidden layer. |
| `PARALLEL_NEURONS` | Number of neurons processed in parallel in each non-input layer. |

These parameters were modifed, extended, and/or removed to support your design.

---

## Suggested Parameter Combinations

### Basic Testing
For basic testing and debugging, these parameters values were used: 
* `TOGGLE_DATA_OUT_READY = 0` (disable backpressure)
* `DATA_IN_VALID_PROBABILITY = 1.0` (disable gaps in input)
* `DEBUG = 1` (print model and inference trace)

### Performance Measurements
To measure latency and throughput, you should use avoid penalities from outside sources: 
* `TOGGLE_DATA_OUT_READY = 0`
* `DATA_IN_VALID_PROBABILITY = 1.0`

### Stress Testing (Contest Requirements)
To fully verify our design's robustness against back-pressure and inputs gaps these values were used:
* `USE_CUSTOM_TOPOLOGY = 0`
* `TOGGLE_DATA_OUT_READY = 1`
* `CONFIG_VALID_PROBABILITY = 0.8`
* `DATA_IN_VALID_PROBABILITY = 0.8`

---
