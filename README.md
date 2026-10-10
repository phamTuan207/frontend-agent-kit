# Frontend Agent Kit

Bộ skill UI/UX dùng chung cho **Codex, OpenCode và CommandCode (`cmd`)** trên Linux. Cài global một lần, dùng trong mọi project.

## Cài nhanh

Cần `git`, `bash`, `python3` và kết nối mạng cho lần tải engine Impeccable đầu tiên. Ba ứng dụng Codex, OpenCode, `cmd` cần được cài riêng.

```bash
git clone https://github.com/phamTuan207/frontend-agent-kit.git
cd frontend-agent-kit
./install.sh
./verify.sh
```

Sau đó **mở phiên mới** trong Codex, OpenCode hoặc `cmd`. Script sao lưu bản skill cùng tên đã có vào `~/.local/share/frontend-agent-kit/backups/` trước khi thay. Nếu mạng chưa sẵn, dùng `./install.sh --no-warm`; Impeccable sẽ tải engine khi gọi lần đầu.

Nếu muốn giao Codex tự làm, clone repo rồi nhắn:

> Đọc `AGENTS.md` của repo này, cài bộ frontend skill cho máy Linux hiện tại, chạy kiểm tra và báo rõ skill nào dùng được trên Codex, OpenCode, CommandCode. Kiểm tra thêm công cụ xem giao diện thật trên máy này, nhưng đừng chép cấu hình GUI từ máy khác.

## Dùng gì khi nào?

**Sổ tay đầy đủ:** [HUONG-DAN.md](HUONG-DAN.md) — bảng chọn từng skill, cách kết hợp, prompt mẫu và cách kiểm tra kết quả.

| Nhu cầu | Gọi skill |
|---|---|
| Thiết kế/xây/review giao diện | **Impeccable** làm hướng chính |
| Chuyển động, timeline, hiệu ứng theo cuộn | Skill **GSAP** phù hợp |
| Component ThreeUI có 3D/shader | **threeui** |
| Xem thêm style, bảng màu, font | **ui-ux-pro-max-reference** theo yêu cầu |
| Thử hướng thẩm mỹ khác cho landing page/portfolio/redesign | **taste-reference** theo yêu cầu |

Quy trình mẫu: **brief rõ mục tiêu và người dùng → Impeccable định hướng/xây → thêm GSAP/ThreeUI nếu cần → mở bản chạy thật để xem desktop/mobile → critique, polish**. Pro Max và Taste là nguồn tham khảo; không cần áp đồng thời cả ba bộ chỉ dẫn thiết kế.

Ví dụ: “Dùng Impeccable thiết kế landing page cho ứng dụng học ngoại ngữ; trước tiên tra Pro Max để đưa 3 hướng màu và font. Sau khi tôi chọn hướng, dùng GSAP ScrollTrigger cho một đoạn cuộn nếu có ích. Mở bản chạy thật trên desktop và mobile rồi sửa lỗi thấy được.”

### Cách gọi trên từng ứng dụng

- **OpenCode:** `/impeccable init`, `/impeccable critique trang chủ`; hoặc nhắn “dùng skill gsap-scrolltrigger…”.
- **Codex:** `$impeccable critique trang chủ`; hoặc nhắn “tra ui-ux-pro-max-reference…”.
- **CommandCode:** nhắn “dùng skill impeccable…”; xem danh sách bằng `cmd skills list --debug`.

## Phạm vi gói

Gói chứa **12 skill**: Impeccable 4.5.0, 8 skill GSAP chính thức, `threeui`, `ui-ux-pro-max-reference`, `taste-reference`. OpenCode có thêm lệnh `/impeccable`. Dữ liệu Pro Max 2.13.0 và Taste v2 được giữ riêng ở `~/.local/share/agent-design-references/`.

`computer-use` và `chromium-cdp` trên máy gốc gắn với môi trường desktop riêng nên không nằm trong gói. Trên máy nhận, dùng công cụ browser/GUI có sẵn để xem UI thật; nếu chưa có, yêu cầu Codex cài hoặc cấu hình công cụ phù hợp máy đó. ThreeUI là thư viện component: skill chỉ hướng dẫn, package `@designcodeio/threeui` được cài vào từng project khi thực sự dùng.

Chi tiết nguồn, phiên bản và giấy phép: [SOURCES.md](SOURCES.md). Các skill được lưu trong repo để `./install.sh` không phải tự tải lại nhiều nguồn; engine Impeccable tải đúng binary Linux khi cần.
