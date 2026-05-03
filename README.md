# BNN_FCC Hardware Design Contest

**Contributors:** Alejandro Paez-Sansonetti, Miguel Sanchez

This repository provides our submission that placed **second** in the EEL6935 Reconfigurable Computing 2 Apple BNN_FCC Hardware Design Contest. The contest represents a collaboration between Apple, Greg Stitt, and EEL6935 Reconfigurable Computing 2 at University of Florida.

We implemented an binary neural network in SystemVerilog with the top-level [bnn_fcc](rtl/bnn_fcc.sv) module, optimizing it for maximum throughput with no constraint on latency.

A top-level interface and testing framework for the binary neural network (BNN), specifically the module implements a fully connected classifier (FCC) was provided by Dr. Stitt, but we designed a more advanced testbench which reaches more coverage over edge cases with directed tests. Our design passes both.


## Design Performance and Area
- **Max Frequency (Out-of-context & Non-restricted):** 945.179 MHz
- **LUT:** 15,568
- **FF:** 34,328
- **LUTAsMem:** 713
- **BRAM:** 53

Measured with probability of configuration and input data stream being valid set to 100%:
- **Throughput:** 112.5 cycles/output
- **Latency:** 394.4 cycles
## Overview

This section provides an overview of the required functionality. See [doc/README.md](doc/README.md) for the original README made for the contest repo. See [rtl/README.md](rtl/README.md) for a detailed description of the bnn_fcc interface. See [verification/README.md](verification/README.md) for a detailed description of the provided testbench and advanced testbench made to reach more coverage.

The bnn_fcc module takes an image input, consisting of 8-bit pixels, and classifies that image into one of multiple possible categories. The module is parameterized to support
any BNN topology, but the contest uses the fully connected (SFC) topology from the following FINN paper:

> Umuroglu, Y., Fraser, N. J., Gambardella, G., Blott, M., Leong, P., Jahre, M., & Vissers, K. (2017). FINN: A Framework for Fast, Scalable Binarized Neural Network Inference. In Proceedings of the 2017 ACM/SIGDA International Symposium on Field-Programmable Gate Arrays (pp. 65-74). DOI: 10.1145/3020078.3021744

The SFC topology is referred to as 784->256->256->10, which means 784 8-bit inputs, one hidden layer with 256 neurons, a second hidden layer with 256 neurons, and an output layer with 10 neurons. The repository provides a model (weights and thresholds) for the SFC topology, which was trained from the [MNIST](https://www.tensorflow.org/datasets/catalog/mnist) dataset for 0-9 digit recognition. Each of the 10 neurons in the output layer corresponds to a single category.

The bnn_fcc module has three different interfaces: configuration, data input, and data output. All three interfaces use the [AXI4-Stream protocol](https://developer.arm.com/documentation/ihi0051/a/) leveraging TKEEP and TLAST.

The configuration interface receives a stream of data that contains the "model" of the network. For a BNN, this model specifies weights and thresholds for every neuron in every layer of the BNN. The exact format of the configuration stream is specified [here](TBD). The design initially parses this configuration stream and configures our own custom on-chip memory hierarchy to feed weights and thresholds to your neuron processing units.

The data input stream provides 8-bit pixels from an image. The bnn_fcc module then uses the provided model (weights and thresholds) to classify that image into a specific category.

The data output stream provides the classified result for the provided input image. 

Since a BNN can only process individual bits, the 8-bit pixels are initially be "binarized" with binarization done by comparing the 8-bit pixel value with 128. If the value is >= 128, the 8-bit pixel is replaced by a 1. Otherwise, it is replaced by a 0.

Neurons in hidden layers always output a 0 or 1. However, the output layer is handled differently. Output layer neurons output their multi-bit "population count", which represents the strength of the classification for that neuron, where each neuron represents one classification category. The BNN then applies an "argmax" across those population counts, which simply assigns the BNN output with the index of the the neuron (i.e., the classified category) that had the largest population count.

## Languages, Tools, FPGA
* **HDL:** SystemVerilog (IEEE 1800-2012)
* **Simulator:** Siemens QuestaSim
* **Synthesis:** Xilinx Vivado 2021.1
* **FPGA:** Xilinx Ultrascale+ 

## Directory Structure
```text
.
├── rtl/                 # Hardware Source Files
|   ├── bnn_fcc.sv       # Top-level DUT (complete this file)
|   └── other files
├── verification/        # Testbench files
|   ├── bnn_fcc_tb.sv
|   ├── bnn_fcc_tb_pkg.sv
|   └── bnn_fcc_coverage_tb # Testbench with added coverage targets
├── slides/              # Slides explaning the project
|   └── TBD
├── sim/                 # Recommended location for simulator project
└── python/              # Python training scripts, reference model, training data, and test vectors
    ├── training_data/   # Weights and Thresholds
    └── test_vectors/
```


We designed a structurally controlled BNN accelerator focused on maximizing throughput, with latency treated as a secondary concern. The design began as an FSM-heavy implementation and was progressively optimized through post-synthesis, post-place, and post-route analysis.

A major theme of the final design is **phase alignment**: control signals are delayed through pipelines so they arrive in sync with the datapath. This allowed us to replace many FSM decisions with deterministic timing, reducing clock-enable fanout, reset fanout, congestion, and routing pressure.

The final architecture uses one main FSM in the configuration manager. Most other control is handled using pipelined valid/last signals, local control pulses, and structurally timed datapath stages.

## Design & Timing Optimization

### Neuron Processor

This README is a concise overview of our submitted report located at [report.pdf](report.pdf).

Each neuron processor is built from a pipelined datapath:

```text
XNOR -> Popcount -> Accumulate -> Threshold
```

The neuron processor has an initial latency of 14 cycles and supports a steady throughput of one result per cycle after the pipeline is filled. Instead of using an FSM inside each neuron processor, control signals such as `valid_out`, `valid_accumulate`, `acc_ld`, and `acc_en` are generated by delaying `valid_in` and `last_in` through fixed pipelines.

This reduced reset and clock-enable logic in dense regions of the design. Only the valid pipeline is reset because other datapath values are ignored unless valid is aligned with them.

The output layer removes the threshold stage because classification only requires the final accumulated scores, saving logic and routing resources.

### Memory Architecture

Memory choice was a major timing factor. LUT-based memory was fast in theory, but caused routing congestion for large weight memories. Block RAM provided better routing predictability for weights, while LUTRAM was still useful for smaller memories such as thresholds.

We used Xilinx `xpm_memory` for weight storage because its configurable read latency allowed Vivado to place output registers closer to the memory. This reduced memory-output routing delay more effectively than manually inserted registers.

Weight memories are always read because incorrect RAM outputs do not matter unless the valid pipeline is aligned with the datapath.

### Layer Architecture

Each layer contains three main components:

```text
Configuration Controller
Activation Input Buffer
Compute Layer
```

The configuration controller loads weights and thresholds. The activation buffer stores layer outputs for reuse, and the compute layer feeds activation data, weights, and thresholds into parallel neuron processors.

The selected layer topology was:

| Layer | PW | PN | Groups |
|---|---:|---:|---:|
| H0 | 64 | 32 | 8 |
| H1 | 32 | 32 | 8 |
| OUT | 32 | 10 | 1 |

The first layer uses width conversion to collect multiple 8-bit input beats into a wider 64-bit word. This reduced the required number of neuron processors and significantly lowered routing pressure.

### Fanout Tree Pipeline

Fanout became one of the main timing bottlenecks after the design reached high frequencies. To address this, we created a parameterized registered fanout tree for both single-bit and bus signals.

Instead of one register driving many destinations, the signal is copied through a tree structure such as:

```text
1 -> 2 -> 4 -> 8 -> 16 -> 32
```

This allowed us to control the tradeoff between register count, routing congestion, and Fmax. Resettable fanout trees were only used for valid signals; non-valid data paths avoided resets to reduce reset fanout.

### Argmax

The original argmax used a large combinational comparison network and became a timing bottleneck. We replaced it with a pipelined reduction tree that compares class scores across multiple stages.

This increased argmax latency but greatly reduced combinational depth, making it much easier to close timing.

### Buffering

Several buffers were added to improve throughput and simplify control:

- **Skid buffer:** prevents input data loss when the first hidden layer stalls.
- **Width conversion FIFO:** converts 8-bit input beats into wider words for the first layer.
- **Ping-pong activation buffers:** allow one buffer to be read while the other is written.
- **Memory-boundary sink buffers:** register memory address, write-enable, and data signals close to RAMs.
- **Output FIFO:** absorbs output backpressure.

These buffers helped isolate timing paths and reduced direct long-distance control/data routing.

### Configuration System

The configuration path was the hardest part to optimize. The original design used large FSMs, but at high frequencies the state bits created critical clock-enable and reset paths.

The configuration manager was reduced to a smaller FSM, while the layer configuration controllers were restructured into mostly structural pipelines. Weight and threshold handling were separated, and valid pulses were used to control when data was meaningful.

This reduced dependence on global control signals and helped the design scale to higher frequencies.

