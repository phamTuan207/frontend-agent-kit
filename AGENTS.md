# Hướng dẫn cho coding agent khi cài repo này

Người dùng muốn thiết lập bộ skill frontend **global** trên một máy Linux có Codex, OpenCode và CommandCode.

1. Đọc `README.md` và `SOURCES.md`. Kiểm tra `bash`, `python3`, `git`, ba ứng dụng và kiến trúc CPU.
2. Chạy `./install.sh`, rồi `./verify.sh`. Script sao lưu bản cùng tên trước khi thay. Nếu mạng không cho tải engine, dùng `./install.sh --no-warm` và báo phần engine cần tải sau.
3. Kiểm tra Codex thấy các skill trong `~/.agents/skills/`; OpenCode thấy các skill đó và `/impeccable`; CommandCode thấy skill bằng `cmd skills list --debug`. Nếu một ứng dụng chưa thấy, mở phiên mới rồi kiểm tra lại theo tài liệu chính thức của ứng dụng.
4. Với kiểm tra UI thật, khảo sát browser/GUI của máy nhận và chọn công cụ phù hợp. `computer-use` và `chromium-cdp` của máy nguồn không được đóng gói vì phụ thuộc môi trường máy đó.
5. Báo lại đường dẫn backup, kết quả từng ứng dụng, và bất cứ bước nào chưa chạy được. Không sao chép bí mật, token, cấu hình cá nhân hoặc file project từ máy khác.

Khi làm frontend sau này: Impeccable dẫn thiết kế; GSAP và ThreeUI áp dụng khi công việc cần; Pro Max và Taste chỉ để tra cứu hoặc so phương án khi được yêu cầu. Xem bảng tra trong `README.md`.
