"""Cycle composition of real-image control and integer fabric execution."""

from models.v4.control_exec import ControlModel
from models.v4.fabric_exec import FabricModel
from models.v4.feeder_exec import ROOT
import json

FEED_IO = json.loads((ROOT / "verification/v4/dataflow/fabric_io.json").read_text())

class ControlFabricModel:
    def __init__(self):
        self.control = ControlModel()
        self.fabric = FabricModel()

    @property
    def image_ready(self):
        return self.control.image_ready

    def wires(self, pins):
        control_pins = dict(pins, exec_ready=0, exec_rsp_valid=0, exec_rsp_fault=0,
                            exec_rsp_job=0, exec_rsp_tag=0, exec_rsp_fmt=0)
        seq = self.control.outputs(control_pins)
        fabric_pins = dict.fromkeys(FEED_IO["inputs"], 0)
        fabric_pins.update(rst=pins["rst"], cancel=seq["exec_cancel"], req_words=seq["exec_words"],
                           req_job=seq["exec_job"], req_tag=seq["exec_tag"], req_fmt=seq["exec_fmt"], req_last=seq["exec_last"],
                           req_valid=seq["exec_valid"] and pins["issue_allow"], req_enable=pins["backend_mask"], req_rev=1,
                           link_ready=pins["link_ready"])
        fab = self.fabric.outputs(fabric_pins)
        control_pins.update(exec_ready=fab["req_ready"] and pins["issue_allow"],
                            exec_rsp_valid=fab["rsp_valid"] and pins["response_allow"], exec_rsp_fault=fab.get("rsp_fault", 0),
                            exec_rsp_job=fab["rsp_job"], exec_rsp_tag=fab["rsp_tag"], exec_rsp_fmt=fab["rsp_fmt"])
        seq = self.control.outputs(control_pins)
        fabric_pins["rsp_ready"] = seq["exec_rsp_ready"] and pins["response_allow"]
        return control_pins, fabric_pins, seq, fab

    def outputs(self, pins):
        _, _, seq, fab = self.wires(pins)
        seq.update({name: fab[name] for name in ("state_acc", "state_rf", "state_valid", "state_preds")})
        seq["result_valid"] = fab["rsp_valid"]
        if not fab["rsp_valid"] and self.control.state == "retire":
            seq.pop("exec_rsp_ready", None)
        if fab["rsp_valid"]:
            seq.update(result_data=fab["rsp_data"], result_fault=fab["rsp_fault"], result_store=fab["rsp_store"])
        return seq

    def tick(self, pins):
        control_pins, fabric_pins, _, _ = self.wires(pins)
        self.control.tick(control_pins)
        self.fabric.tick(fabric_pins)
