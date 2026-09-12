"""Integer transactional fabric oracle with explicit issue/link/retire timing."""

from copy import deepcopy

from compiler.v4.context_image import OPERANDS, REVISION
from models.v4.context_exec import decode, FIELDS
from models.v4.feeder_exec import evaluate as feed
from models.v4.pe_exec import AW, SW, AMASK, SMASK, signed
from models.v4.tile_exec import TileModel

def pack(values, width):
    return sum((value & ((1 << width)-1)) << (index*width) for index, value in enumerate(values))

class FabricModel:
    def __init__(self):
        self.tiles = [TileModel(tile) for tile in range(32)]
        self.links = [[None]*4 for _ in range(32)]
        self.state = "idle"
        self.meta = dict(rsp_job=0, rsp_tag=0, rsp_fmt=0, rsp_last=0, rsp_feed_fault=0)
        self.arrays = []
        self.results = []
        self.candidates = []
        self.routes = []
        self.request = None
        self.operands = None

    def outputs(self, pins):
        active = not (pins["rst"] or pins["cancel"])
        ready = self.state == "error" or (self.state == "exec" and all(array["stage"] == "done" for array in self.arrays))
        result = dict(self.meta, req_ready=int(active and self.state == "idle"), rsp_valid=int(active and ready))
        result.update(state_acc=pack([tile.alu.acc for tile in self.tiles], AW),
                      state_rf=pack([pack(tile.rf, SW) for tile in self.tiles], 8*SW),
                      state_valid=pack([tile.valid for tile in self.tiles], 8),
                      state_preds=pack([tile.preds for tile in self.tiles], 3))
        if ready:
            faults = [item["rsp_fault"] for item in self.results] if self.state == "exec" else [0]*32
            failed = bool(self.meta["rsp_feed_fault"] or any(faults))
            result.update(rsp_fault=int(failed), rsp_faults=pack(faults, 4),
                          rsp_data=pack([item["rsp_data"] for item in self.results], SW) if self.state == "exec" else 0,
                          rsp_acc=pack([item["rsp_acc"] for item in self.results], AW) if self.state == "exec" else 0,
                          rsp_exec=pack([item["rsp_exec"] for item in self.results], 1) if not failed else 0,
                          rsp_store=pack([item["rsp_store"] for item in self.results], 1) if not failed else 0,
                          rsp_halt=pack([item["rsp_halt"] for item in self.results], 1) if not failed else 0)
        return result

    def execute(self):
        pins, operands = self.request, self.operands
        self.results, self.candidates, self.routes = [], [], []
        latencies = []
        for tile_id, current in enumerate(self.tiles):
            word = pins["req_words"] >> (tile_id*64) & ((1 << 64)-1)
            dec, fault = decode(word, pins["req_rev"], pins["req_alu_mode"], tile_id, routing=True)
            raw_routes = word >> FIELDS["routeN"][0] & 4095
            link_data = [entry[0] if entry else 0 for entry in self.links[tile_id]]
            link_valid = sum(int(entry is not None and entry[1:] == (pins["req_job"], pins["req_fmt"])) << side
                             for side, entry in enumerate(self.links[tile_id]))
            if fault:
                dec, _ = decode(0, REVISION, 0, tile_id, routing=True)
            request = dict(rst=0, cancel=0, req_valid=1, rsp_ready=0,
                           req_mode=pins["req_alu_mode"], req_mat=operands["rsp_mat"] >> (tile_id*SW) & SMASK,
                           req_vec=operands["rsp_vec"] >> (tile_id*SW) & SMASK,
                           req_mat_valid=pins["req_operands"], req_vec_valid=pins["req_operands"], req_links=pack(link_data, SW),
                           req_link_valid=link_valid & sum(int(-(1 << (SW-1)) <= signed(value, AW) < (1 << (SW-1))) << side for side, value in enumerate(link_data)),
                           req_lane=(operands["rsp_mask"] >> tile_id & 1) if not fault else 0,
                           req_job=pins["req_job"], req_tag=pins["req_tag"], req_fmt=pins["req_fmt"], req_last=pins["req_last"])
            request.update({"req_"+name: value for name, value in dec.items() if name not in ("wide", "wide_idx", "store", "halt")})
            request["req_wide"] = link_data[dec["wide_idx"]] if dec["wide"] else 0
            request["req_wide_valid"] = int(bool(dec["wide"] and link_valid >> dec["wide_idx"] & 1))
            candidate = deepcopy(current)
            candidate.tick(request)
            latency = 1
            request.update(req_valid=0)
            if candidate.alu.response is None:
                candidate.tick(request)
                latency += 1
            response = candidate.outputs(request)
            response["rsp_fault"] = fault or response["rsp_fault"]
            response["rsp_exec"] = 0 if fault else response["rsp_exec"]
            response["rsp_store"] = int(dec["store"] and response["rsp_exec"] and not response["rsp_fault"])
            response["rsp_halt"] = int(dec["halt"] and response["rsp_exec"] and not response["rsp_fault"])
            route_value = current.alu.acc & AMASK if dec["a_kind"] == OPERANDS["ACC"] else link_data[dec["a_idx"] % 4]
            value_valid = dec["a_kind"] == OPERANDS["ACC"] or (dec["a_kind"] == OPERANDS["LINK"] and link_valid >> (dec["a_idx"] % 4) & 1)
            transfers = []
            if response["rsp_exec"]:
                for side in range(4):
                    selector = raw_routes >> (3*side) & 7
                    if selector == 1 and not value_valid:
                        response["rsp_fault"] |= 6
                    if selector:
                        data = {1: route_value, 2: current.alu.acc & AMASK,
                                3: signed(response["rsp_data"], SW) & AMASK}.get(selector, 0)
                        transfers.append((side, data))
            request["rsp_ready"] = 1
            candidate.tick(request)
            self.candidates.append(candidate)
            self.results.append(response)
            self.routes.append(transfers)
            latencies.append(latency)
        self.arrays = [dict(stage="exec", delay=max(latencies[start:start+16])-1, pending=set(), staged=[])
                       for start in (0, 16)]

    def tick(self, pins):
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__()
            return
        if before["rsp_valid"] and pins["rsp_ready"]:
            if not before["rsp_fault"]:
                self.tiles = self.candidates
                for array in self.arrays:
                    for source, side, data in array["staged"]:
                        dest = source + (-4, 1, 4, -1)[side]
                        self.links[dest][(side+2)%4] = (data, self.meta["rsp_job"], self.meta["rsp_fmt"])
            self.state = "idle"
            return
        if self.state == "idle" and pins["req_valid"]:
            self.request = pins.copy()
            self.operands = feed(pins) if pins["req_operands"] else dict(rsp_fault=0, rsp_mat=0, rsp_vec=0, rsp_mask=(1 << 32)-1)
            self.operands["rsp_mask"] &= pins["req_enable"]
            self.meta = {"rsp_"+name: pins["req_"+name] for name in ("job", "tag", "fmt", "last")}
            self.meta["rsp_feed_fault"] = 0
            self.state = "feed"
        elif self.state == "feed":
            self.meta["rsp_feed_fault"] = self.operands["rsp_fault"]
            if self.operands["rsp_fault"]:
                self.state = "error"
            else:
                self.execute()
                self.state = "exec"
        elif self.state == "exec":
            for cluster, array in enumerate(self.arrays):
                start = cluster*16
                if array["stage"] == "exec":
                    if array["delay"]:
                        array["delay"] -= 1
                    else:
                        array["stage"] = "done" if any(item["rsp_fault"] for item in self.results[start:start+16]) else "route"
                elif array["stage"] == "route":
                    array["pending"] = {(source, side, data) for source in range(start, start+16) for side, data in self.routes[source]}
                    array["stage"] = "links"
                elif array["stage"] == "links":
                    if not array["pending"]:
                        array["stage"] = "done"
                    else:
                        accepted = {entry for entry in array["pending"] if pins["link_ready"] >> (entry[0]*4+entry[1]) & 1}
                        array["staged"].extend(accepted)
                        array["pending"] -= accepted
