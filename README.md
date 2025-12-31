# Optimized Implementation of Falcon Verify on Cortex-M4

This code is an implementation of the paper titled [**"Optimized Falcon Verify on Cortex-M4 for Post-Quantum Secure UAV Communication"**](https://www.sciencedirect.com/science/article/pii/S2405959524001401).

---
## Optimization strategy

We apply signed Plantard multiplication to the NTT in Falcon Verify.

The detailed optimization strategys are as follow:

* Packing two coefficients per register
* Using Plantard multiplication instead Montgomery multiplication
* Appling layer-merging to NTT/iNTT
    * **3-3-3/3-3-4 layer merging** to Falcon-512/Falcon-1024 NTT
    * **4-3-2/4-3-3 layer merging** to Falcon-512/Falcon-1024 iNTT
* Applying lazy reduction to NTT/iNTT
    * Performing reductions after **3-layer and 6-layer** during NTT
    * Through **loop unrolling**, the reduction is performed only on the registers that require reductions

---
## Benchmark

We use the [**pqm4**](https://github.com/mupq/pqm4) framwork to measure the performance of the **Verify** function, and **STM32CubeIDE** to measure the performance of NTT.

The benchmark settings in STM32CubeIDE are as follow:
* Frequency : 20MHz (same as **pqm4**)
* Compile option : -O3