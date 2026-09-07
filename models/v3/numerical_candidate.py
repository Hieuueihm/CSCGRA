"""Explicit opt-in quality candidates; production defaults remain unchanged."""
from dataclasses import replace
from models.v3 import hardware

NAMES = ("production", "quality_f17", "quality_f17_floor2", "quality_f17_floor4",
         "quality_f17_s23", "quality_d22", "cosamp_data_d27_shift18_r32")


def configuration(name):
    if name == "production":
        return hardware.NumericProfile(), hardware.RefinementPolicy()
    if name == "quality_f17":
        return (replace(hardware.NumericProfile(), data_f=17, solver_f=22),
                replace(hardware.RefinementPolicy(), strict_normal_residual_shift=16))
    if name in ("quality_f17_floor2", "quality_f17_floor4"):
        shift = 2 if name == "quality_f17_floor2" else 4
        return (replace(hardware.NumericProfile(), data_f=17, solver_f=22),
                replace(hardware.RefinementPolicy(), strict_normal_residual_shift=18,
                        quantization_floor_shift=shift))
    if name == "quality_d22":
        return (replace(hardware.NumericProfile(), data_w=22, data_f=18,
                        solver_w=31, solver_f=23, acc_w=70),
                replace(hardware.RefinementPolicy(), strict_normal_residual_shift=16))
    if name == "quality_f17_s23":
        return (replace(hardware.NumericProfile(), data_f=17, solver_f=23),
                replace(hardware.RefinementPolicy(), strict_normal_residual_shift=18,
                        quantization_floor_shift=2))
    if name == "cosamp_data_d27_shift18_r32":
        return (replace(hardware.NumericProfile(), data_w=27, data_f=23,
                        solver_w=31, solver_f=23, acc_w=70),
                replace(hardware.RefinementPolicy(), strict_normal_residual_shift=18,
                        reliable_recompute_interval=32))
    raise ValueError(f"unknown numerical candidate: {name}")
