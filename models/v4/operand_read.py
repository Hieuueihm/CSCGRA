"""Independent coordinate planner and split-response operand reader oracle."""

from models.v4.memory_exec import FAULT, SW, CW, field, packed
from models.v4.feeder_exec import FeederModel

def plan(pins):
    mode, trans, rows, cols, out, red, step, base = (pins[name] for name in ("mode", "trans", "rows", "cols", "out_idx", "red_idx", "step", "vec_base"))
    dense, rfour = mode >= 2, mode in (1, 3)
    transpose = bool(trans) if dense else rfour
    outputs, reductions = (cols, rows) if transpose else (rows, cols)
    fault = 0
    if not 1 <= rows <= 128 or not 1 <= cols <= (96 if dense else 1024):
        fault = FAULT["SHAPE"]
    elif out >= outputs or red >= reductions or out % (8 if rfour else 32) or (rfour and red%32) or (not rfour and step) or (not dense and bool(trans) != rfour):
        fault = FAULT["RANGE"]
    matrix, vector, banks, lanes = {}, {}, [0]*4, 0
    if not fault:
        for output in range(out, min(outputs, out+(8 if rfour else 32))):
            for lane in range(4 if rfour else 1):
                reduction = red + (8*lane+step if rfour else 0)
                if reduction >= reductions:
                    continue
                row, col = (reduction, output) if transpose else (output, reduction)
                bank = (row+col)%32 if dense else col%8
                address = row*((cols+31)//32)+col//32 if dense else (col//8)*((rows+31)//32)+row//32
                if bank in matrix and matrix[bank] != address:
                    fault = FAULT["RANGE"]
                matrix[bank] = address
                index = base+reduction
                if index >= 4096:
                    fault = FAULT["RANGE"]
                else:
                    vector[index%32] = index//32
                    banks[lane] = index%32
                    lanes |= 1 << lane
    if fault:
        matrix, vector, banks, lanes = {}, {}, [0]*4, 0
    return dict(mat_mask=sum(1 << bank for bank in matrix), vec_mask=sum(1 << bank for bank in vector),
                mat_addr=packed([matrix.get(bank, 0) for bank in range(32)], 9),
                vec_addr=packed([vector.get(bank, 0) for bank in range(32)], 7),
                vec_banks=packed(banks, 5), vec_lanes=lanes, fault=fault)

class PlanModel:
    def outputs(self, pins):
        return plan(pins)

    def tick(self, pins):
        pass

class ReaderModel:
    def __init__(self):
        self.state = "idle"
        self.req = dict(req_mode=0, req_vec_plane=0, req_trans=0, req_rows=0, req_cols=0, req_out=0, req_red=0, req_step=0,
                        req_scale=0, req_key=0, req_mat_generation=0, req_vec_generation=0, req_job=0, req_tag=0, req_fmt=0, req_last=0)
        self.plan = dict(mat_mask=0, vec_mask=0, mat_addr=0, vec_addr=0, vec_banks=0, vec_lanes=0, fault=0)
        self.sent = [False, False]
        self.received = [False, False]
        self.faults = [0, 0]
        self.fault = self.matrix = self.masks = self.mask = self.vector = 0
        self.feeder = FeederModel()

    def feed_pins(self, pins):
        feed = self.req.copy()
        feed.update(rst=pins["rst"], cancel=pins["cancel"], req_valid=int(self.state == "feed"), rsp_ready=int(self.state == "wait" and pins["rsp_ready"]),
                    req_signs=self.matrix & ((1 << 256)-1), req_masks=self.masks, req_sign_valid=self.mask & 255,
                    req_dense=self.matrix, req_dense_valid=self.mask, req_vec=self.vector, req_vec_valid=self.plan["vec_lanes"], req_src_fault=0)
        return feed

    def outputs(self, pins):
        active = not (pins["rst"] or pins["cancel"])
        feed = self.feeder.outputs(self.feed_pins(pins))
        result = dict(req_ready=int(active and self.state == "idle"), mat_valid=int(active and self.state == "read" and not self.sent[0]),
                      vec_valid=int(active and self.state == "read" and not self.sent[1]),
                      mat_rsp_ready=int(active and self.state == "read" and self.sent[0] and not self.received[0]),
                      vec_rsp_ready=int(active and self.state == "read" and self.sent[1] and not self.received[1]),
                      mat_dense=int(self.req["req_mode"] >= 2), mat_mask=self.plan["mat_mask"], mat_addr=self.plan["mat_addr"],
                      mat_key=self.req["req_key"], mat_generation=self.req["req_mat_generation"],
                      vec_plane=self.req["req_vec_plane"], vec_mask=self.plan["vec_mask"], vec_addr=self.plan["vec_addr"], vec_generation=self.req["req_vec_generation"],
                      mem_job=self.req["req_job"], mem_tag=self.req["req_tag"], mem_fmt=self.req["req_fmt"],
                      rsp_job=self.req["req_job"], rsp_tag=self.req["req_tag"], rsp_fmt=self.req["req_fmt"], rsp_last=self.req["req_last"],
                      rsp_valid=int(active and (self.state == "error" or (self.state == "wait" and feed["rsp_valid"]))),
                      rsp_fault=self.fault if self.state == "error" else (FAULT["SOURCE"] if feed["rsp_fault"] else 0))
        for name in ("mat", "vec", "mask"):
            result["rsp_"+name] = feed["rsp_"+name] if self.state == "wait" and not feed["rsp_fault"] else 0
        return result

    def tick(self, pins):
        before = self.outputs(pins)
        feed_pins = self.feed_pins(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__()
            return
        received_before = all(self.received)
        if pins["req_valid"] and before["req_ready"]:
            self.req = {name: pins[name] for name in self.req}
            self.plan = plan(dict(mode=pins["req_mode"], trans=pins["req_trans"], rows=pins["req_rows"], cols=pins["req_cols"],
                                  out_idx=pins["req_out"], red_idx=pins["req_red"], step=pins["req_step"], vec_base=pins["req_vec_base"]))
            self.sent = [self.plan["mat_mask"] == 0, self.plan["vec_mask"] == 0]
            self.received = self.sent.copy()
            self.matrix = self.masks = self.mask = self.vector = 0
            self.faults = [0, 0]
            self.fault = self.plan["fault"] or (FAULT["PLANE"] if pins["req_vec_plane"] > 2 else FAULT["SHAPE"])
            error = self.plan["fault"] or pins["req_vec_plane"] > 2 or (pins["req_mode"] < 2 and not 0 < pins["req_scale"] < (1 << 17))
            self.state = "error" if error else "read"
        else:
            for source, name in enumerate(("mat", "vec")):
                if before[name+"_valid"] and pins[name+"_ready"]:
                    self.sent[source] = True
                if before[name+"_rsp_ready"] and pins[name+"_rsp_valid"]:
                    self.received[source] = True
                    if name == "mat":
                        self.matrix, self.masks, self.mask = pins["mat_rsp_data"], pins["mat_rsp_masks"], pins["mat_rsp_mask"]
                    else:
                        self.vector = packed([field(pins["vec_rsp_data"], field(self.plan["vec_banks"], lane, 5), SW) if self.plan["vec_lanes"] >> lane & 1 else 0 for lane in range(4)], SW)
                    if any(pins[name+"_rsp_"+meta] != self.req["req_"+meta] for meta in ("job", "tag", "fmt")) or pins[name+"_rsp_generation"] != self.req["req_"+name+"_generation"]:
                        self.faults[source] = FAULT["TAG"]
                    elif pins[name+"_rsp_fault"] or pins[name+"_rsp_mask"] != self.plan[name+"_mask"]:
                        self.faults[source] = FAULT["SOURCE"]
            if self.state == "read" and received_before:
                self.fault = self.faults[0] or self.faults[1]
                self.state = "error" if self.fault else "feed"
            elif self.state == "feed":
                self.state = "wait"
            if before["rsp_valid"] and pins["rsp_ready"]:
                self.state = "idle"
        self.feeder.tick(feed_pins)
