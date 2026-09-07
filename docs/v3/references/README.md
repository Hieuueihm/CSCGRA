# v3 primary paper sources

File này lưu tám nguồn primary dùng để định nghĩa mathematical golden v3 và
các nguồn CGRA dùng để định nghĩa architecture/compiler contract.
DOI là định danh chuẩn; link PDF/open-access chỉ là đường truy cập thuận tiện.
Nếu nội dung giữa bản mirror và bản xuất bản khác nhau, ưu tiên bản gắn với DOI.

## Danh mục nhanh

| ID v3 | Paper | Nguồn chuẩn | Bản đọc/PDF |
| --- | --- | --- | --- |
| OMP | Tropp & Gilbert, *Signal Recovery From Random Measurements Via Orthogonal Matching Pursuit* | [DOI](https://doi.org/10.1109/TIT.2007.909108) | [Author PDF](https://users.cms.caltech.edu/~jtropp/papers/TG07-Signal-Recovery.pdf) |
| CoSaMP | Needell & Tropp, *CoSaMP: Iterative Signal Recovery from Incomplete and Inaccurate Samples* | [DOI](https://doi.org/10.1016/j.acha.2008.07.002) | [Caltech record](https://authors.library.caltech.edu/records/gabgd-m9s11), [CORE PDF](https://fileserver-az.core.ac.uk/download/pdf/82326678.pdf) |
| IHT | Blumensath & Davies, *Iterative Hard Thresholding for Compressed Sensing* | [DOI](https://doi.org/10.1016/j.acha.2009.04.002) | [Publisher page](https://www.sciencedirect.com/science/article/pii/S1063520309000384) |
| HTP | Foucart, *Hard Thresholding Pursuit: An Algorithm for Compressive Sensing* | [DOI](https://doi.org/10.1137/100806278) | [Author PDF](https://foucart.github.io/publi/HTP_Final.pdf) |
| SP | Dai & Milenkovic, *Subspace Pursuit for Compressive Sensing Signal Reconstruction* | [DOI](https://doi.org/10.1109/TIT.2009.2016006) | [arXiv](https://arxiv.org/abs/0803.0811) |
| GP | Blumensath & Davies, *Gradient Pursuits* | [DOI](https://doi.org/10.1109/TSP.2007.916124) | [Edinburgh PDF](https://www.pure.ed.ac.uk/ws/portalfiles/portal/17821386/Gradient_Pursuits.pdf) |
| gOMP | Wang, Kwon & Shim, *Generalized Orthogonal Matching Pursuit* | [DOI](https://doi.org/10.1109/TSP.2012.2218810) | [arXiv](https://arxiv.org/abs/1111.6664) |
| MP | Mallat & Zhang, *Matching Pursuits With Time-Frequency Dictionaries* | [DOI](https://doi.org/10.1109/78.258082) | [Author PDF](https://www.di.ens.fr/~mallat/papiers/MallatPursuit93.pdf) |

## Citation và phần được dùng trong v3

### 1. OMP

J. A. Tropp and A. C. Gilbert, “Signal recovery from random measurements via
orthogonal matching pursuit,” *IEEE Transactions on Information Theory*,
vol. 53, no. 12, pp. 4655–4666, Dec. 2007.

V3 dùng vòng lặp OMP: correlation, chọn một atom mới, least squares trên toàn
support và cập nhật residual. Paper giả thiết atom được normalize; matrix
Bernoulli v3 có các cột đồng norm nên normalized ranking vẫn xác định rõ.

### 2. CoSaMP

D. Needell and J. A. Tropp, “CoSaMP: Iterative signal recovery from incomplete
and inaccurate samples,” *Applied and Computational Harmonic Analysis*,
vol. 26, no. 3, pp. 301–321, May 2009.

Nguồn normative là Algorithm 1: identify `2K`, merge với support cũ, LS trên
union, prune về `K`, rồi cập nhật residual. V3 không thêm debias LS sau prune.

### 3. IHT

T. Blumensath and M. E. Davies, “Iterative hard thresholding for compressed
sensing,” *Applied and Computational Harmonic Analysis*, vol. 27, no. 3,
pp. 265–274, Nov. 2009.

V3 dùng phép cập nhật `x + mu*A^T*(y-Ax)` rồi hard-threshold về `K`. Giá trị
`mu` là gradient step/normalization được lưu trong case manifest; nó không phải
regularization của LS.

### 4. HTP

S. Foucart, “Hard thresholding pursuit: An algorithm for compressive sensing,”
*SIAM Journal on Numerical Analysis*, vol. 49, no. 6, pp. 2543–2563, 2011.

V3 dùng biến thể `HTP_mu` được paper định nghĩa: chọn Top-K từ
`x + mu*A^T*(y-Ax)`, sau đó giải ordinary LS trên support vừa chọn.

### 5. SP

W. Dai and O. Milenkovic, “Subspace pursuit for compressive sensing signal
reconstruction,” *IEEE Transactions on Information Theory*, vol. 55, no. 5,
pp. 2230–2249, May 2009.

V3 giữ initialization riêng, union workspace tối đa `2K`, LS trên union, prune,
LS cuối trên `K`, và rollback/stop nếu residual không giảm.

### 6. GP

T. Blumensath and M. E. Davies, “Gradient pursuits,” *IEEE Transactions on
Signal Processing*, vol. 56, no. 6, pp. 2370–2382, Jun. 2008.

V3 dùng Basic GP: gradient `A^T*r`, direction là gradient restricted trên
support, và exact residual line search. Re-selection atom đã có trong support
được phép; đây là một phần của semantics GP.

### 7. gOMP

J. Wang, S. Kwon, and B. Shim, “Generalized orthogonal matching pursuit,”
*IEEE Transactions on Signal Processing*, vol. 60, no. 12, pp. 6202–6216,
Dec. 2012.

Mỗi iteration chọn đúng `L` atom mới rồi giải LS trên toàn support. Với profile
`L=2`, v3 phải chứa support/workspace tới `2K`; không trim group cuối để ép
support về `K`.

### 8. MP

S. G. Mallat and Z. Zhang, “Matching pursuits with time-frequency
dictionaries,” *IEEE Transactions on Signal Processing*, vol. 41, no. 12,
pp. 3397–3415, Dec. 1993.

V3 dùng normalized correlation, cho phép re-selection, rank-one coefficient
update và residual projection. Hardware profile hiện chỉ chấp nhận dictionary
có equal-norm columns để raw fixed-point comparator tương đương normalized
selection.

## Quy tắc sử dụng

1. Khi sửa `models/v3/paper.py`, đối chiếu paper trong file này trước.
2. Không lấy blog, implementation hoặc RTL cũ làm nguồn thay cho paper.
3. Tie-break, finite iteration budget và fixed-point fault policy phải được ghi
   là harness/hardware policy, không được mô tả thành công thức của paper.
4. Nếu đổi thuật toán so với nguồn trên, tạo algorithm/build ID mới thay vì giữ
   nguyên tên paper profile.
5. DOI trong `models/v3/paper.py`, bảng này và phase manifest phải thống nhất.

## CGRA architecture and compiler sources

| Vai trò trong v3 | Nguồn |
| --- | --- |
| Taxonomy, interconnect/RF/context DSE, ADRES case study | B. De Sutter, P. Raghavan and A. Lambrechts, *Coarse-Grained Reconfigurable Array Architectures*, 2010. Local reviewed copy: `C:\Users\gbmhi\Downloads\2010HSPSdesutter.pdf`. |
| Dynamically reconfigurable, statically scheduled template | B. Mei et al., *ADRES: An Architecture with Tightly Coupled VLIW Processor and Coarse-Grained Reconfigurable Matrix*, FPL 2003. |
| Retargetable architecture model and routing-aware compilation | B. Mei et al., *DRESC: A Retargetable Compiler for Coarse-Grained Reconfigurable Architectures*, 2002, [imec publication record](https://imec-publications.be/entities/publication/69644528-81d7-4b4c-970a-6563e0a1993b). |
| Joint placement, routing and modulo scheduling | H. Park et al., *Modulo Graph Embedding: Mapping Applications onto Coarse-Grained Reconfigurable Architectures*, CASES 2006, [author PDF](https://cccp.eecs.umich.edu/papers/parkhc-cases06.pdf), DOI `10.1145/1176760.1176778`. |
| Edge/route-centric modulo scheduling | H. Park et al., *Edge-Centric Modulo Scheduling for Coarse-Grained Reconfigurable Architectures*, PACT 2008. |
| Reconfigurable interconnect and compile-time routing | M. Karunaratne et al., *HyCUBE: A CGRA with Reconfigurable Single-cycle Multi-hop Interconnect*, DAC 2017, [author PDF](https://www.comp.nus.edu.sg/~tulika/DAC17.pdf), DOI `10.1145/3061639.3062262`. |
| Dual 4x4 array, shared synchronous context, reduced constant memory and heterogeneous PE placement | H. L. Pham et al., *MRCA 2.0: Area-Optimized Multi-grained Reconfigurable Cryptographic Accelerator for Securing Blockchain-based IoT Systems*, IEEE Micro draft, 2024. Local reviewed copy: `C:\Users\gbmhi\Downloads\IEEE_Micro (2).pdf`. |

Các nguồn trên dẫn tới lựa chọn v3: 4x4, distributed context, static per-cycle
schedule, explicit route reservation, local RF/route latch trong MRRG và
predication. V3 không copy tight CPU coupling của ADRES và không copy
combinational multi-hop của HyCUBE vào FPGA baseline.

MRCA 2.0 dẫn tới shared-context baseline: hai cluster 4x4 vẫn là hai fabric
vật lý nhưng corresponding tile nhận cùng một tile context và dùng một
`array_context_pc`. Điều này phù hợp các routine PS 32-lane vốn chạy cùng opcode
trên các row/column khác nhau và giảm 32 tile plane xuống 16. V3 revision 4
không copy local-RF double buffer;
RF chỉ có 8 entry một bank để tránh bank-swap state. Constant/scalar file dùng
chung thay vì constant RAM trong từng PE.

Không copy các phần crypto-specific của MRCA 2.0: không có 8/32/64-bit carry
concatenation, S-box, MixColumn hay crypto CFU. A62 reduction, generated-Phi,
TOP-K và scalar divide vẫn là sidecar theo workload sparse reconstruction;
reciprocal/sqrt chỉ giữ reserved encoding trong active build.
V3 không copy heterogeneous PE placement của MRCA 2.0. Tám bank 72 bit vẫn tạo
16 S27 element/stripe, nhưng general multiply được đặt trong một homogeneous
vector sidecar thay vì buộc capability vào column PE. Paper chỉ là bằng chứng
cho cách tổ chức shared context và workload-specific sidecar, không phải authority
cho placement arithmetic của sparse reconstruction.

## Generated-Phi implementation sources

| Vai trò | Nguồn |
| --- | --- |
| Counter-based PRNG và Threefry/Philox | J. K. Salmon, M. A. Moraes, R. O. Dror and D. E. Shaw, *Parallel Random Numbers: As Easy as 1, 2, 3*, SC 2011, [author PDF](https://www.thesalmons.org/john/random123/papers/random123sc11.pdf), DOI `10.1145/2063384.2063405`. |
| Bit-exact algorithm và known-answer vectors | D. E. Shaw Research, [Random123 official repository](https://github.com/DEShawResearch/random123), `Threefry2x32-20`. |
| Bằng chứng sử dụng hiện đại cho reproducible/vectorizable parallel PRNG | JAX, [PRNG design](https://docs.jax.dev/en/latest/jep/263-prng.html) và [current random API](https://docs.jax.dev/en/latest/jax.random.html); default implementation là `threefry2x32`. |

V3 dùng thuật toán Threefry chuẩn và KAT chính thức; phần riêng của kiến trúc là
mapping `(seed,column,row_block)` sang Bernoulli sign, pipeline gập hai lượt và
đường `PHI_APPLY_SYMBOL` và runtime normalizer. JAX chỉ là bằng chứng Threefry vẫn được dùng trong hệ
thống song song hiện đại, không phải nguồn chứng minh compressed-sensing.

## RIP và generated-matrix qualification sources

| Vai trò | Nguồn |
| --- | --- |
| Dense subgaussian/Rademacher random matrix có RIP với xác suất cao | R. Baraniuk, M. Davenport, R. DeVore and M. Wakin, *A Simple Proof of the Restricted Isometry Property for Random Matrices*, Constructive Approximation 2008, [DOI](https://doi.org/10.1007/s00365-007-9003-x). |
| Không thể coi runtime checker là exact RIP oracle | A. S. Bandeira, E. Dobriban, D. G. Mixon and W. F. Sawin, *Certifying the Restricted Isometry Property is Hard*, [arXiv](https://arxiv.org/abs/1204.1580). |
| RIP condition là nền tảng guarantee của CoSaMP | D. Needell and J. A. Tropp, *CoSaMP: Iterative Signal Recovery from Incomplete and Inaccurate Samples*, [CaltechAUTHORS](https://authors.library.caltech.edu/records/qwm56-fvw26), DOI `10.1016/j.acha.2008.07.002`. |
| Ví dụ condition theo order `3K` cho HTP | S. Foucart, *Hard Thresholding Pursuit: An Algorithm for Compressive Sensing*, [author PDF](https://foucart.github.io/publi/HTP_Final.pdf), DOI `10.1137/100806278`. |
| Structured fast operator có RIP nhưng đổi datapath thành convolution/subsampling | H. Rauhut, J. Romberg and J. A. Tropp, *Restricted Isometries for Partial Random Circulant Matrices*, [CaltechAUTHORS](https://authors.library.caltech.edu/records/4bmf1-thv07), DOI `10.1016/j.acha.2011.05.001`. |
| Hardware gần đây dùng LFSR để tránh full-matrix storage, nhưng không phải per-seed RIP proof | S. Bose et al., *Sense-Now Reconstruct-Later*, npj Unconventional Computing 2026, [article](https://www.nature.com/articles/s44335-026-00083-3). |

Vì exact RIP certification khó, v3 tách rõ `ensemble theorem`, `qualified seed
manifest` và `empirical recovery sweep`. Không gọi LFSR/Threefry statistical
test là chứng minh RIP.
