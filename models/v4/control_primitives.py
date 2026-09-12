"""Combinational control and synchronous context-memory integer oracles."""

from models.v4.control_exec import decode, FAULT

class DecodeModel:
    def outputs(self, pins):
        dec, fault = decode(pins["word"], pins["rev"])
        return dict(kind=dec["kind"], count=dec["count"], loop_target=dec["loop_target"],
                    branch_target=dec["branch_target"], predicate=dec["predicate"], address_mode=dec["address_mode"],
                    address=dec["immediate_address"], stride=dec["stride"], fault=fault)

    def tick(self, pins):
        pass

class StoreModel:
    def __init__(self):
        self.memory = {}
        self.pending = False
        self.payload = dict(rsp_words=0, rsp_control=0, rsp_pc=0, rsp_generation=0, rsp_fault=0)

    def outputs(self, pins):
        active = not (pins["rst"] or pins["cancel"] or pins["invalidate"])
        return dict(self.payload, rd_ready=int(active and not self.pending and not pins["wr_en"]),
                    rsp_valid=int(active and self.pending))

    def tick(self, pins):
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"] or pins["invalidate"]:
            self.pending = False
            self.payload = dict.fromkeys(self.payload, 0)
            return
        if pins["wr_en"] and pins["wr_bank"] <= 32:
            self.memory[(pins["wr_pc"], pins["wr_bank"])] = pins["wr_data"] & ((1 << (256 if pins["wr_bank"] == 32 else 64))-1)
        if before["rsp_valid"] and pins["rsp_ready"]:
            self.pending = False
        if pins["rd_valid"] and before["rd_ready"]:
            self.pending = True
            good = pins["image_ready"] and pins["generation"] == pins["rd_generation"]
            self.payload = dict(rsp_words=sum(self.memory[(pins["rd_pc"], bank)] << (64*bank) for bank in range(32)) if good else 0,
                                rsp_control=self.memory[(pins["rd_pc"], 32)] if good else 0, rsp_pc=pins["rd_pc"],
                                rsp_generation=pins["rd_generation"], rsp_fault=0 if good else FAULT["FETCH"])
