# Bắt đầu với `jocv` — hướng dẫn từng bước

File này là hướng dẫn thực hành, cầm tay chỉ việc, để chạy `jocv` trên
**bất kỳ máy Linux nào bạn quản lý** (EC2, VPS, on-prem, máy nhà...). Nội
dung dưới đây không phụ thuộc vào nhà cung cấp hạ tầng cụ thể nào — dùng
EC2 hay không không quan trọng, chỉ cần một máy Linux SSH được vào.

Muốn hiểu kiến trúc/tham chiếu guide gốc thì xem [README.md](README.md);
muốn hiểu cấu trúc `networks/` thì xem [networks/README.md](networks/README.md).

Hướng dẫn này tập trung vào **`ROLE=validator`** (Option 2 — đường đã được
guide gốc xác thực đầy đủ). Nếu bạn muốn thử `ROLE=el-cl`/`all`, đọc mục
["Option 3 caveat"](README.md#option-3-caveat-el-cl-roles) trong README
trước — phần đó chưa được JOC/JBF xác nhận.

## 0. Chuẩn bị trước khi bắt đầu

- [ ] Một máy Linux (Ubuntu/Debian được hỗ trợ tốt nhất; Amazon Linux/RHEL-
      family cũng chạy được nhưng ít được kiểm chứng hơn — xem `jocv install`
      bên dưới) mà bạn SSH vào được và có quyền `sudo`.
- [ ] Đã có **receiver withdrawal address** (Step 1-1 trong guide gốc — địa
      chỉ ví do JBF/admin cấp).
- [ ] Đã join JOC PoSA network trên BCCloud (Step 1-2).
- [ ] Có chỗ ghi mnemonic offline (giấy + bút, hoặc tương tự). **Không**
      copy-paste mnemonic vào đâu khác ngoài màn hình terminal lúc đó.
- [ ] Máy chỉ cần mở SSH (22) ở firewall/security group — `ROLE=validator`
      không nhận kết nối inbound nào khác, chỉ gọi ra ngoài tới Consensus
      HTTP API trên BCCloud.
- [ ] Ghi lại **public IP** của máy này — cần điền vào ô "Source" khi mở
      Consensus HTTP API trên BCCloud (Step 2-5 trong guide gốc).

## 1. Lấy code về máy

```bash
git clone git@github.com:anhnhx131/joc-docker.git
cd joc-docker
```

(Nếu máy chưa có SSH key add vào GitHub, dùng URL https thay thế:
`git clone https://github.com/anhnhx131/joc-docker.git`.)

## 2. Cài Docker

```bash
./jocv install
```

Lệnh này:
- Kiểm tra Docker đã có chưa — nếu có rồi thì báo và dừng, không làm gì
  thêm (an toàn để chạy lại nhiều lần).
- Nếu chưa có: in ra **toàn bộ** các lệnh `sudo` sẽ chạy, hỏi xác nhận một
  lần, rồi mới thực thi (theo đúng các bước chính thức từ
  [docs.docker.com](https://docs.docker.com/engine/install/), không dùng
  kiểu `curl | sh` mù mờ).
- Thêm user hiện tại vào group `docker` để chạy không cần `sudo`.

Nếu vừa được thêm vào group `docker`, **logout SSH rồi login lại** (hoặc
chạy `newgrp docker`) trước khi tiếp tục — group mới chỉ có hiệu lực ở
phiên đăng nhập mới.

Kiểm tra lại:

```bash
docker --version
docker compose version
```

> `jocv install` chỉ cài Docker — không tinh chỉnh OS (swappiness, NTP...),
> không cài thêm gói nào khác. Nếu distro của bạn không được hỗ trợ, lệnh
> sẽ báo rõ và trỏ tới hướng dẫn cài Docker chính thức để bạn tự làm.

## 3. Đặt file config mạng (Step 2-1 trong guide gốc)

`jocv` không tự tải được `config.yaml`/`deposit_contract_block.txt` vì
trang JOC là trang HTML, không phải raw file. Bạn tải tay:

1. Mở https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/
2. Tải `config.yaml` và `deposit_contract_block.txt`.
3. Đặt cả hai vào `networks/mainnet/cl/` trên máy đang chạy `jocv`:

```bash
# ví dụ dùng scp từ máy đã tải file
scp config.yaml deposit_contract_block.txt \
  your-user@<ip-may-chay-jocv>:~/joc-docker/networks/mainnet/cl/
```

Cách khác, sạch hơn về lâu dài: commit 2 file này vào repo `joc-docker`
của công ty (xem README mục "Updating config via git"), rồi chỉ cần
`git pull` ở bước này.

## 4. Chạy `jocv init`

```bash
./jocv init
```

Bạn sẽ được hỏi tuần tự — đây là những gì sẽ xảy ra, theo đúng thứ tự:

1. **`Which network? [mainnet]:`** — Enter để dùng mainnet (mặc định).
2. **`Which role? [validator]:`** — Enter để dùng `validator` (mặc định,
   đúng Option 2).
3. Script kiểm tra `config.yaml`/`deposit_contract_block.txt` đã có ở
   bước 3 chưa — nếu thiếu sẽ báo lỗi và dừng lại, in lại hướng dẫn.
4. **`Enter the receiver withdrawal address obtained in Step 1-1 (0x...):`**
   — dán địa chỉ ví JBF/admin đã cấp (Step 1-1). Sai định dạng sẽ bị từ
   chối, không lo nhập lộn.
5. Tool tự sinh `password.txt` ngẫu nhiên, `chmod 600`.
6. Tool chạy lệnh sinh mnemonic (mất vài giây, không cần mạng).
7. **Mnemonic sẽ được in ra MÀN HÌNH DUY NHẤT MỘT LẦN** — dạng:
   ```
   ================================================================
    MNEMONIC — write this down OFFLINE now. It will only be shown once:

    comic oven rent shock ... (12-24 từ)

   ================================================================
   ```
   **Dừng lại, ghi tay ra giấy ngay lúc này.** Đừng chụp màn hình, đừng
   copy vào file/note/chat nào.
8. **`Have you securely written down this mnemonic OFFLINE? Type 'yes' to continue:`**
   — chỉ gõ `yes` sau khi đã ghi xong. Gõ gì khác sẽ dừng lại, không tạo
   key gì cả (an toàn, không mất gì).
9. Tool tạo `keystore-xxx.json`, `deposit_data-xxx.json`, xoá mnemonic khỏi
   bộ nhớ, `clear` màn hình.
10. Tool import key vào Lighthouse, tạo `.env`, chạy
    `docker compose up -d`.
11. Cuối cùng in ra đường dẫn `deposit_data-xxx.json` (cần cho Step 3-1 —
    Launchpad) và cảnh báo bảo mật.

Nếu có gì gõ sai giữa chừng: `jocv init` **an toàn để chạy lại** — nó tự
phát hiện phần nào đã xong (key đã có, `.env` đã có...) và hỏi trước khi
ghi đè, không tự xoá gì.

## 5. Việc phải làm tay trên BCCloud (không có trong `jocv`)

Ở giữa lúc này, sang tab khác làm trên [BCCloud](https://app.bccloud.net/)
(xem chi tiết trong guide gốc, hoặc bảng ở đầu README.md):

1. **Step 2-3**: Tạo Transaction Cluster (2 relay node, region Tokyo).
2. **Step 2-4**: Tạo Validator Cluster, thêm **External Validator** node,
   điền `pubkey` lấy từ `deposit_data-xxx.json` (đường dẫn `jocv init` vừa
   in ra ở bước 4.11).
3. **Step 2-5**: Mở Consensus HTTP API trên node đó, giới hạn Source IP =
   **public IP của máy đang chạy `jocv`** (đã ghi ở bước 0). Ghi lại IP
   của node BCCloud đó — bạn cần nó ở bước tiếp theo.

## 6. Trỏ Validator Client vào BCCloud

```bash
./jocv beacon set http://<ip-node-bccloud>:3500
```

Lệnh này cập nhật `.env` và tự `docker compose up -d` lại container.

## 7. Kiểm tra

```bash
./jocv status
```

Kỳ vọng thấy container `validator` đang `Up`, log gần nhất không có lỗi
kết nối. Nếu thấy `Not attesting` lặp lại liên tục hơn 15-20 phút (sau 5-10
phút khởi động đầu), có vấn đề — xem log chi tiết:

```bash
./jocv logs validator
```

## 8. Nộp deposit data (Step 3-1)

Mở Launchpad theo URL JBF cung cấp, upload đúng file
`data/validator_keys/deposit_data-xxx.json` (đường dẫn đã in ra ở bước 4).
Sau đó theo dõi trạng thái Active theo Step 3-2 trong guide gốc bằng
`./jocv status`.

## Vài lỗi thường gặp

| Triệu chứng | Nguyên nhân / cách xử lý |
| --- | --- |
| `docker: permission denied` sau `jocv install` | Chưa áp dụng group `docker` mới — logout/login lại SSH, hoặc chạy `newgrp docker`. |
| `jocv install` báo "Unsupported/unrecognized distro" | Distro của bạn chưa được cover — cài Docker theo [hướng dẫn chính thức](https://docs.docker.com/engine/install/) rồi chạy lại `jocv install` (nó sẽ thấy Docker đã có và bỏ qua). |
| `jocv init` báo thiếu `config.yaml` | Chưa đặt file vào `networks/mainnet/cl/` (Bước 3) — kiểm tra lại tên file, đúng thư mục. |
| `Invalid address` khi nhập withdrawal address | Phải là `0x` + đúng 40 ký tự hex (42 ký tự tổng). Copy nhầm thiếu/thừa ký tự là lỗi hay gặp nhất. |
| `docker compose up` báo thiếu image `execution` dù đang dùng `ROLE=validator` | Không nên xảy ra — nếu gặp, báo lại, đây là bug (role `validator` không được đụng tới service `execution`/`beacon`). |
| Muốn làm lại từ đầu hoàn toàn | Dừng container (`./jocv down`), xoá `data/` và `.env`, chạy lại `./jocv init`. **Chỉ làm việc này nếu chưa nộp deposit data** — nếu đã nộp rồi mà xoá key thì mất khả năng vận hành validator đó. |

## Sau khi test xong trên 1 network/role

Đổi `NETWORK` hay `ROLE` sau khi đã `init` **không được hỗ trợ** — key và
deposit data gắn với 1 network cụ thể. Muốn thử network/role khác, dùng
một checkout mới (`git clone` lại vào thư mục khác), đừng sửa `.env` của
bản đang chạy thật.
