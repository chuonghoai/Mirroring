# Rà soát pháp lý: Cà phê Đồi Sương (site demo)

> Báo cáo này được tạo bằng cách chạy vn-law-check trên [`demo/site/`](./site/). Đây là site giả lập, cố ý để lại những lỗi thường gặp ở shop nhỏ Việt Nam.

**Ngày audit:** 02/11/2026
**Kết quả quét:** mức 2 (bán hàng), có AI, có dịch vụ nước ngoài ([output đầy đủ](./scan-output.txt))
- Giỏ hàng: `index.html:17`, `:30`
- Đăng nhập: `index.html:18`
- Form thu thập họ tên/email/SĐT: `index.html:41`
- Google Analytics + Facebook Pixel: `index.html:7-10`
- Chatbot gọi OpenAI: `api/chat.js:4`
- Lưu dữ liệu trên Firebase: `api/subscribe.js:5`
- Host trên Vercel: `vercel.json`

**Quy mô:** hộ kinh doanh (`index.html:59`) → được miễn một phần theo Điều 39 Luật 91/2025
**Phạm vi:** 01 Dữ liệu cá nhân · 02 Thương mại điện tử · 04 Bảo vệ người tiêu dùng · 07 Minh bạch AI

## Tổng quan

| Lĩnh vực | 🔴 | 🟡 | 🟢 |
|---|---|---|---|
| Bảo vệ dữ liệu cá nhân | 4 | 0 | 1 |
| Thương mại điện tử | 2 | 0 | 1 |
| Bảo vệ người tiêu dùng | 0 | 2 | 0 |
| Minh bạch AI | 1 | 0 | 0 |

**Không áp dụng:**
- An ninh mạng: không xử lý dữ liệu quy mô lớn, không có nội dung người dùng đăng công khai.
- Quảng cáo: không bán chỗ quảng cáo, không hợp tác KOL. Facebook Pixel đã xét ở mục 01-C.
- Giao dịch điện tử: chỉ đặt hàng thông thường, không ký hợp đồng hay dùng chữ ký điện tử.

## 🔴 Cần xử lý ngay

**1. Chính sách bảo mật dẫn văn bản đã hết hiệu lực, thiếu quyền của người dùng**: 01-A
- `chinh-sach-bao-mat.html:6` ghi "Căn cứ Nghị định 13/2023/NĐ-CP". NĐ 13 hết hiệu lực từ 01/01/2026, đã được NĐ 356/2025/NĐ-CP thay thế.
- Chính sách không nêu quyền xem, sửa, xóa, rút đồng ý của người dùng, không có kênh để yêu cầu, không ghi thời gian lưu trữ.
- Chính sách không kể tên các bên thứ ba nhận dữ liệu: Google, Meta, OpenAI, Firebase.
- Căn cứ: Điều 4 khoản 1 Luật 91/2025/QH15; Điều 5 NĐ 356/2025/NĐ-CP (thời hạn xử lý yêu cầu).
- Đề xuất: viết lại chính sách theo Luật 91/2025 + NĐ 356/2025, thêm mục quyền của người dùng kèm email tiếp nhận yêu cầu, liệt kê đủ bên thứ ba.

**2. Coi việc "tiếp tục sử dụng website" là đồng ý**: 01-B
- `chinh-sach-bao-mat.html:12`: "Bằng việc tiếp tục sử dụng website, bạn được xem là đã đồng ý với chính sách này."
- Căn cứ: Điều 9 khoản 4 điểm d Luật 91/2025/QH15: im lặng hoặc không phản hồi không được coi là đồng ý.
- Đề xuất: bỏ câu này. Xin đồng ý rõ ràng tại đúng chỗ thu thập dữ liệu (form, checkout).

**3. Ô "đồng ý nhận email khuyến mãi" được tích sẵn**: 01-B
- `index.html:45`: `<input type="checkbox" name="marketing" checked>`
- Căn cứ: Điều 9 Luật 91/2025/QH15 (đồng ý phải tự nguyện, rõ ràng); NĐ 356/2025/NĐ-CP cấm tích sẵn mặc định (số điều cần tra cứu lại).
- Đề xuất: bỏ thuộc tính `checked`, lưu thời điểm người dùng tích vào (`api/subscribe.js` đang chỉ lưu giá trị `marketing`, không lưu thời điểm).

**4. Google Analytics và Facebook Pixel chạy ngay khi tải trang**: 01-C
- `index.html:7-10`: hai script nạp vô điều kiện, không có banner xin đồng ý.
- Căn cứ: Điều 28 Luật 91/2025/QH15 (xử lý dữ liệu cho quảng cáo cần đồng ý và phải có cách từ chối); NĐ 356/2025 xếp dữ liệu theo dõi hành vi trực tuyến vào nhóm nhạy cảm.
- Đề xuất: thêm banner cookie, chỉ nạp GA/Pixel sau khi người dùng bấm đồng ý, và cho phép từ chối mà vẫn mua hàng được.

**5. Không thấy dấu hiệu đã thông báo website với Bộ Công Thương**: 02-B
- Footer (`index.html:58-61`) không có logo/link xác nhận của online.gov.vn.
- Căn cứ: Điều 14 Luật 122/2025/QH15: nền tảng bán hàng trực tiếp có chức năng đặt hàng phải thông báo. Nếu đã thông báo theo quy định cũ thì được hoạt động theo nội dung đã đăng ký đến 30/06/2027 (Điều 41), khi đó chỉ cần gắn logo.
- Đề xuất: kiểm tra trên online.gov.vn. Chưa thông báo thì làm thủ tục, xong thì gắn logo ở footer.

**6. Thiếu thông tin và chính sách bắt buộc**: 02-C
- Footer chỉ có tên hộ kinh doanh và hotline (`index.html:59-60`). Thiếu: mã số thuế/số đăng ký hộ kinh doanh, email, địa chỉ cụ thể.
- Site không có: chính sách đổi trả, chính sách vận chuyển, cơ chế khiếu nại.
- Căn cứ: Điều 11 Luật 122/2025/QH15.
- Đề xuất: bổ sung thông tin vào footer, thêm 3 trang chính sách.

**7. Chatbot AI đóng vai nhân viên thật**: 07-B
- Widget hiển thị "Chị Lan, tư vấn viên" kèm ảnh đại diện (`index.html:52`). System prompt yêu cầu AI nhận là "chị Lan, nhân viên tư vấn" (`api/chat.js:10`). Người dùng không có cách nào biết mình đang nói chuyện với AI.
- Tin nhắn khách gõ vào được gửi sang OpenAI, nhưng chính sách bảo mật không nhắc tới việc này.
- Căn cứ: Điều 11 khoản 1 Luật 134/2025/QH15: người dùng phải biết mình đang tương tác với AI.
  - Luật hiệu lực 01/03/2026.
  - Nếu chatbot chạy từ trước ngày đó thì có 12 tháng chuyển tiếp, tức đến 01/03/2027 (Điều 35).
- Đề xuất: đổi tên thành "Trợ lý AI của Đồi Sương", bỏ ảnh người thật, sửa system prompt. Ghi vào chính sách bảo mật việc tin nhắn được xử lý bởi OpenAI.

## 🟡 Nên cải thiện

**8. Phí phát sinh chỉ hiện ở bước thanh toán**: 04-A
- `checkout.html:9`: "Phí xử lý đơn: 15.000đ" không xuất hiện ở trang sản phẩm hay giỏ hàng.
- Căn cứ: Điều 21 Luật 19/2023/QH15 (cung cấp thông tin về giá).
- Đề xuất: ghi rõ phí này từ trang sản phẩm, hoặc gộp vào giá.

**9. Giá gạch và đồng hồ flash sale cần kiểm chứng**: 04-E
- Giá gạch 250.000đ (`index.html:29`) phải là giá đã thực sự bán trước đó.
- Đồng hồ "Flash sale còn 00:59:59" (`index.html:23`) là chữ tĩnh, code không có logic đếm ngược hay ngày kết thúc. Nếu khuyến mãi không có thời hạn thật thì đây là thông tin gây áp lực mua hàng sai sự thật.
- Căn cứ: Điều 10 Luật 19/2023/QH15 (hành vi bị cấm).
- Đề xuất: giữ bằng chứng về giá cũ. Gắn đồng hồ với ngày kết thúc thật, hoặc bỏ đồng hồ.

## 🟢 Đạt yêu cầu
- Có trang chính sách bảo mật, link ở footer (`index.html:61`), nhưng nội dung cần sửa theo mục 1.
- Có hotline liên hệ (`index.html:60`).

## Miễn trừ áp dụng
Footer ghi đây là hộ kinh doanh (`index.html:59`). Theo Điều 39 Luật 91/2025/QH15, site được miễn:
- đánh giá tác động xử lý dữ liệu (01-E)
- hồ sơ chuyển dữ liệu xuyên biên giới (01-D), dù dữ liệu đang được gửi sang Firebase và OpenAI
- chỉ định nhân sự bảo vệ dữ liệu (01-E)

Miễn trừ mất hiệu lực nếu shop xử lý dữ liệu nhạy cảm hoặc dữ liệu số lượng lớn. Miễn trừ cũng không bỏ được nghĩa vụ công khai và xin đồng ý ở các mục 1-4.

## Mức phạt tham khảo (cho các mục 🔴 về dữ liệu cá nhân)
- Xử lý dữ liệu không có đồng ý (mục 3, 4): 30-50 triệu đồng (NĐ 330/2026/NĐ-CP).
- Coi im lặng là đồng ý (mục 2): 50-70 triệu đồng (NĐ 330/2026/NĐ-CP).
- Trần chung với các hành vi khác: 3 tỷ đồng với tổ chức, 1/2 mức đó với cá nhân (Điều 8 khoản 5, 6 Luật 91/2025/QH15).
- Mức phạt cho mục 5-7 (TMĐT, AI): chưa xác minh được nghị định xử phạt.

Đây là mức tối đa theo quy định tham khảo được, không phải mức site chắc chắn sẽ bị phạt.

## Giới hạn & khuyến nghị
> Báo cáo do AI tạo dựa trên bộ checklist tổng hợp từ văn bản pháp luật công khai, **không phải ý kiến tư vấn pháp lý chính thức**. Một số số điều trong checklist chưa đối chiếu được với toàn văn. Trước khi quyết định, hãy xác minh lại văn bản tại thuvienphapluat.vn/vbpl.vn và tham vấn luật sư.
