# Sổ tay dùng skill frontend

> **Nhớ một dòng:** Impeccable chọn hướng và xây giao diện; GSAP làm chuyển động; ThreeUI thêm component 3D; Pro Max và Taste cho phương án tham khảo. Luôn xem bản chạy thật trước khi chốt.

## Chọn đúng skill

| Bạn cần | Skill | Nói với agent |
|---|---|---|
| Trang, app, dashboard, form đẹp và dễ dùng | `impeccable` | “Dùng Impeccable thiết kế và xây màn hình đăng ký cho người mới.” |
| Hiệu ứng xuất hiện, chuỗi chuyển động, animation theo cuộn | `gsap-*` | “Dùng `gsap-scrolltrigger` làm đoạn reveal theo cuộn, hỗ trợ người tắt hiệu ứng.” |
| Một component 3D/shader trong trang React | `threeui` | “Tìm component ThreeUI Community hợp phần hero và tích hợp vào project.” |
| Ba lựa chọn style, màu, font, biểu đồ để so | `ui-ux-pro-max-reference` | “Tra Pro Max cho ba hướng màu và font của trang này; giải thích vì sao hợp.” |
| Một hướng thẩm mỹ khác cho landing page, portfolio, redesign | `taste-reference` | “Tra Taste và đề xuất một phương án khác với thiết kế hiện tại.” |

**Pro Max và Taste là nguồn tham khảo theo yêu cầu.** Khi đã chọn một hướng, để Impeccable dẫn phần xây dựng. Không cần gọi tất cả skill trong một prompt.

## Khi nào kết hợp?

| Tình huống | Thứ tự dễ dùng |
|---|---|
| Giao diện thông thường | Impeccable → mở bản chạy thật → `critique`/`polish` |
| Chưa rõ gu | Tra Pro Max **hoặc** Taste → chọn hướng → Impeccable → xem bản thật |
| Landing page cần chuyển động | Impeccable → GSAP theo yêu cầu cụ thể → xem desktop/mobile |
| Hero cần 3D | Impeccable → ThreeUI → GSAP chỉ nếu cần chuyển cảnh → xem desktop/mobile |
| Chỉ sửa hiệu ứng đang lỗi | Skill GSAP liên quan → chạy trang, cuộn/thao tác để kiểm tra |

**Ví dụ prompt đầy đủ:**

> Thiết kế trang giới thiệu ứng dụng học ngoại ngữ cho người đi làm. Tra Pro Max, đưa ba hướng màu và font để tôi chọn. Sau khi chọn, dùng Impeccable xây trang. Phần kể câu chuyện theo cuộn dùng GSAP nếu giúp người đọc hiểu hơn. Mở bản chạy thật ở desktop và mobile, kiểm tra chữ, nút, tốc độ và hiệu ứng rồi sửa.

## Chọn skill GSAP con

| Skill | Việc chính |
|---|---|
| `gsap-core` | Chuyển động đơn giản, thời gian, easing (nhịp nhanh/chậm) |
| `gsap-timeline` | Ghép nhiều hiệu ứng theo thứ tự |
| `gsap-scrolltrigger` | Hiệu ứng theo cuộn, ghim một đoạn khi cuộn, chuyển động nhiều lớp |
| `gsap-react` | GSAP trong React/Next.js, dọn hiệu ứng khi component đóng |
| `gsap-frameworks` | GSAP trong Vue/Svelte và framework khác |
| `gsap-plugins` | Flip, Draggable, SplitText và plugin khác |
| `gsap-performance` | Hiệu ứng giật, chậm, tốn tài nguyên |
| `gsap-utils` | Các hàm hỗ trợ tính toán của GSAP |

Chỉ chọn skill khớp việc. Nếu project đã dùng thư viện animation khác, nói rõ để agent giữ đúng công nghệ của project.

## Gọi trong từng ứng dụng

| Ứng dụng | Cách nhanh |
|---|---|
| **OpenCode** | `/impeccable init`, `/impeccable critique trang chủ`; với skill khác, nói “dùng skill `gsap-react`…” |
| **Codex** | `$impeccable critique trang chủ`; hoặc nhắn “dùng skill `threeui`…” |
| **CommandCode (`cmd`)** | Nhắn “dùng skill `impeccable`…”; xem skill đã nạp bằng `cmd skills list --debug` |

**Lệnh Impeccable hay dùng:** `init` ghi ngữ cảnh sản phẩm; `shape` lên hướng; `critique` nhận xét trải nghiệm và hình thức; `audit` soi khả năng dùng bằng bàn phím/đọc màn hình, khả năng thích ứng desktop/mobile và tốc độ; `polish` hoàn thiện; `adapt` chỉnh cho mobile/tablet. Mở **đúng thư mục project** trước khi gọi.

## Kiểm tra sau khi xây

1. Chạy app và mở giao diện thật bằng browser/GUI trên máy đó.
2. Xem ít nhất desktop và mobile; thử cuộn, bấm nút, nhập form, trạng thái lỗi và trạng thái rỗng.
3. Sửa vấn đề nhìn thấy, rồi nhờ Impeccable `critique` hoặc `audit` phần quan trọng.

Gói này **không cài `computer-use` hoặc `chromium-cdp`** vì hai công cụ trên máy nguồn phụ thuộc desktop riêng. Máy nhận có thể dùng browser/GUI khác; nhờ Codex kiểm tra và chọn công cụ phù hợp nếu cần.

## Nếu agent không thấy skill

- Chạy `./verify.sh`, rồi mở **phiên mới** của ứng dụng.
- Kiểm tra có skill cùng tên bên trong project (`.agents/skills`, `.opencode/skills`, `.claude/skills`) vì bản project có thể ghi đè bản global.
- Với OpenCode, `/impeccable` là lệnh riêng; các GSAP/ThreeUI/skill tham khảo có thể gọi bằng tên trong lời nhắn.
- Xem cách cài và vị trí backup trong [README.md](README.md); nguồn và giấy phép trong [SOURCES.md](SOURCES.md).
