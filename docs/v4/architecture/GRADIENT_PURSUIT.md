# GP: Gradient Pursuit

Yêu cầu ngày 2026-09-09: GP phải theo đúng gradient. Tham chiếu
[Blumensath & Davies, phần III và III-A](https://www.pure.ed.ac.uk/ws/portalfiles/portal/17821386/Gradient_Pursuits.pdf).
Với ký hiệu project, một vòng là:

```text
r = y - Phi*x
g = Phi^T*r                  // hướng âm gradient của 0.5*||y-Phi*x||²
i = argmax |g_i|             // cho phép chọn lại atom
S = S union {i}
d_S = g_S; d_ngoai_S = 0
q = Phi*d = B*d_S
alpha = (r^T*q)/(q^T*q)
x_new = x + alpha*d
```

Support giữ thứ tự chọn, không nhân đôi atom khi chọn lại. Line search cập
nhật toàn bộ hệ số trên support. GP không dùng threshold top-K sau gradient
hoặc bước cố định `step_size` của IHT. K truth, số vòng và support thực được
ghi riêng; một vòng chọn lại atom không làm support tăng.
Phi trong profile hiện hành có cùng norm cho mọi cột; xếp hạng có chia norm
trong model và TOP1 theo trị tuyệt đối trong compiler cho cùng thứ tự.

Model [recovery.py](../../../models/v4/recovery.py) và compiler
[recovery_emit.py](../../../compiler/v4/recovery_emit.py) hiện dùng đúng chuỗi
restricted gradient/adaptive line search này. Context chạy transpose,
TOP1/UNION/APPLY_SUPPORT, forward của d, DOT/ENERGY/DIV, SCALE/ADD, STORE X24,
forward của nghiệm đã lưu, residual và commit.

Không thay tử số `r^T*q` bằng `g_S^T*g_S` trong fixed point: q và g đã qua
các lần làm tròn khác nhau. Mẫu số bằng 0 trả stationary và giữ kết quả đã
chấp nhận. Residual được tính từ nghiệm lưu X24.

Sparse forward chỉ thay cách cấp cùng các tích qua B; giữ gradient toàn N,
line search và cập nhật các hệ số support cũ. Các cặp xsim cùng input khớp
X/residual/support/status. Sau sparse forward và pipeline dùng chung:
M32/N128/K2 hai vòng 7866 -> 3866 chu kỳ; M64/N256/K8 tám vòng
93611 -> 26739. [Ca M128/N1024/K2 hai vòng](../../../reports/v4/pipeline_max_program_comparison_20260909/README.md)
giảm 164775 -> 26985. Bật lịch sparse bằng `sparse_forward=True`; default
vẫn giữ đường full Phi. Đây chưa phải held-out ứng dụng.

GP mặc định V2 là full-gradient/IHT-like theo báo cáo signoff; cycle đó chỉ
giữ làm lịch sử, không làm ngưỡng chấp nhận GP chuẩn. So sánh trực tiếp phải
cùng phương trình, dữ liệu, số vòng, rounding và phạm vi đếm cycle.

[Kiểm numerical bổ sung](../../../verification/v4/test_gp_gradient_contract.py)
đã PASS ba ca: finite-difference/line minimum, rounding của tử số line search,
và bảy vòng chọn lại trên chỉ hai atom. Ca rounding cho thấy dùng g_S^T*g_S
thay r^T*q làm lệch hai đơn vị X24. Đây là kiểm model/VM; bằng chứng RTL
vẫn là các chương trình chạy bằng Vivado đã lưu riêng.
