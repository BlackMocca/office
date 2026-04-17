# core/OOXML — การแก้ไขสำหรับ edoc-office

เอกสารนี้บันทึกการแก้ไขที่ทำใน `core/OOXML` สำหรับ edoc-office  
(upstream: https://github.com/ONLYOFFICE/DocumentServer)

---

## 1. Thai Distributed Alignment — `<w:br/>` ใน ForceSave & Converter

### ปัญหา

หลังจาก ForceSave เอกสารที่มี `<w:jc w:val="thaiDistribute"/>` จะไม่มี `<w:br/>` ใน DOCX ที่ได้ออกมา หรือ break positions ผิด ทำให้ server-side render ไม่ตรงกับที่เห็นใน editor

### Root Cause

**JS side (`Serialize2.js`)** inject `<w:br/>` โดยอาศัย layout ที่ render แล้ว:

```javascript
var lbLinesCount = par.GetLinesCount(); // ต้องการ paragraph ที่ถูก recalculate แล้ว
if (!bUseSelection && lbLinesCount > 1) {
    // inject c_oSerRunType::linebreak bytes
}
```

`GetLinesCount()` คืนค่า 0 ถ้า `IsRecalculated() = false`  
→ Paragraph ที่อยู่นอก viewport (virtual scrolling) จะ `IsRecalculated = false`  
→ ไม่มี `linebreak` bytes ใน binary → C++ ไม่มีอะไรแปลงเป็น `<w:br/>`

### Architecture (ForceSave Flow)

```
Browser editor
  └─ Serialize2.js → binary
        ↓
CoAuthoring service (port 8000)
        ↓
x2t converter
  └─ BinaryReaderD.cpp → DOCX XML
        ↓
DOCX file
```

---

### วิธีแก้ (C++ side) — Font-Metrics Line Breaking

ใช้ font metrics จริง + page dimensions + paragraph indent คำนวณตำแหน่งตัดบรรทัด เหมือนที่ JS ทำ

**ไฟล์ที่สร้าง/แก้ไข:**

| ไฟล์ | การเปลี่ยนแปลง |
|------|----------------|
| `BinReader/ThaiWordBreaker.h` | **NEW** Thai word segmenter (maximum matching) |
| `BinReader/ThaiWordBreaker.cpp` | **NEW** Implementation: load `words_th.txt`, segment Thai sequences |
| `BinReader/fontTableWriter.h` | เพิ่ม `GetFontManager()` getter |
| `BinReader/StylesWriter.h` | เพิ่ม `m_oDocDefaultRPr`, `m_mapStyleRPr` (styleId → rPr) |
| `BinReader/BinaryReaderD.h` | เพิ่ม member variables + method declarations (ดูด้านล่าง) |
| `BinReader/BinaryReaderD.cpp` | algorithm หลัก (ดูด้านล่าง) |
| `Projects/Linux/BinDocument/BinDocument.pro` | เพิ่ม `ThaiWordBreaker.cpp` |
| `Dockerfile` | copy `words_th.txt` → 2 paths ใน container |

**Member variables ที่เพิ่มใน `BinaryReaderD.h`:**

```cpp
bool   m_bIsThaiDistribute;      // true ตลอด paragraph ที่มี jcThaiDistribute
double m_dPageTextWidthPt;       // ความกว้าง text area จริง (จาก sectPr)
double m_dThaiAccumWidthPt;      // accumulated line width ข้าม runs ใน paragraph เดียว
bool   m_bThaiFirstLineDone;     // false = ยังอยู่บรรทัดแรก (firstLine indent ยังใช้อยู่)
int    m_nThaiPendingCppBreaks;  // C++ breaks ที่ insert แล้วแต่ยังไม่ได้ match กับ JS break
```

---

### Algorithm

#### 1. Pre-scan Page Dimensions (`PreScanForPageDimensions`)

เรียกก่อน `READ_TABLE_DEF` เพื่อดึงขนาดหน้ากระดาษก่อน paragraph ใดๆ ถูกอ่าน (body-level sectPr อยู่ท้าย stream)

```
GetPos() → save nSavedPos
GetLong() → totalLen
scan body cells (READ1_DEF format):
  ถ้า type == c_oSerParType::sectPr:
    scan sectPr cells (READ1_DEF format):
      ถ้า type == pgSz หรือ pgMar:
        scan leaf cells (READ2_DEF format: type:1 + lenType:1 + data:N):
          WTwips  → dPageWidthMm
          LeftTwips / RightTwips → dLeftMm / dRightMm
    m_dPageTextWidthPt = (W - Left - Right) * 72/25.4
    break
  else:
    GetPointer(len)  ← skip
Seek(nSavedPos) ← restore stream
```

> **หมายเหตุ Binary Format:** sectPr leaf cells ใช้ READ2_DEF (`type:1 + lenType:1 + data:N`) ไม่ใช่ READ1_DEF (`type:1 + len:4 + data`)

#### 2. Font Resolution

```
Priority  Source                  Field
1         run rPr                 m_oRFonts.{m_sCs, m_sEastAsia, m_sAscii}
2         paragraph style rPr     m_mapStyleRPr[styleId]
3         document defaults        m_oDocDefaultRPr
4         fallback                 12pt, ไม่มี font name
```

#### 3. JS Linebreak Handling — Balance Strategy

```
ReadRunContent(linebreak):
  if m_bIsThaiDistribute:
    if m_nThaiPendingCppBreaks > 0:
      m_nThaiPendingCppBreaks--        ← absorb JS break (C++ already broke here)
    else:
      emit <w:br/>                     ← pass through JS break
    m_dThaiAccumWidthPt = 0.0
    m_bThaiFirstLineDone = true
  else:
    emit <w:br/>
```

**Strategy:**
- **On-screen** (`IsRecalculated=true`): JS inject linebreaks หลัง measure จริง → ปกติ pass through
- **Off-screen** (`IsRecalculated=false`): ไม่มี JS linebreaks → C++ คำนวณเองทั้งหมด
- **Balance**: ถ้า C++ insert break ก่อน JS (cross-run overflow) → `m_nThaiPendingCppBreaks++` → JS break ถัดมาถูก absorb เพื่อไม่ให้บรรทัดเกิน

> **ตัวอย่าง:** JS วางbreak หลัง "และ" (คิดว่า "สัตว์ต่าง ๆ และ" พอดีบรรทัด)  
> แต่ C++ วัดแล้ว "สัตว์ต่าง ๆ" เต็มแล้ว → C++ break ก่อน "และ" + pending=1  
> → JS break หลัง "และ" ถูก absorb → ผล: "สัตว์ต่าง ๆ | และการเปลี่ยนแปลง..."

#### 4. `WriteThaiDistributeRunText` — Segment + Measure + Break

```
1. Resolve font name + size (priority chain ด้านบน)
2. Compute effective line width:
     dBodyWidthPt  = m_dPageTextWidthPt - start_indent - end_indent
     dFirstWidthPt = dBodyWidthPt - firstLine_indent  (หรือ + hanging)
     getEffectiveWidth() = m_bThaiFirstLineDone ? dBodyWidthPt : dFirstWidthPt
3. Load font: IFontManager::LoadFontByName(name, sizePt, 0, 72, 72) + AfterLoad()
4. ThaiWordBreaker::Segment(text) → words[]
5. for each word (i):
     if i == 0 (first word of run):
       cross-run overflow check:
         if accum > 0 AND seg starts with Thai AND accum + width > effectiveWidth:
           flushAndBreak()   ← m_nThaiPendingCppBreaks++
           accum = width(seg)
         else:
           accum += width(seg)
     else (i > 0, Thai↔Thai boundary only):
       dSegWidth = Σ MeasureChar2(char).fAdvanceX  (skip IsThaiCombining chars)
       if m_dThaiAccumWidthPt + dSegWidth > effectiveWidth:
         trim trailing spaces จาก sAccum
         flush sAccum → <w:t>
         flushAndBreak()   ← m_nThaiPendingCppBreaks++
         m_dThaiAccumWidthPt = dSegWidth
       else:
         m_dThaiAccumWidthPt += dSegWidth
     sAccum += word
6. trim trailing spaces จาก sAccum (ป้องกัน renderer word-wrap + ลด accum carry-over)
7. flush remaining sAccum → <w:t>
```

**Thai Combining Mark Filter (`IsThaiCombining`):**  
Skip U+0E31, U+0E34–U+0E3A, U+0E47–U+0E4E ในการวัด advance width  
(เหล่านี้ไม่มี advance width จริง แต่ IFontManager อาจคืนค่า non-zero → overcount ~56pt/บรรทัด)

---

### Bugs ที่แก้ระหว่าง Implementation

| Bug | สาเหตุ | วิธีแก้ |
|-----|--------|---------|
| SIGABRT crash ทุก document | `PreScanForPageDimensions` อ่าน pgSz/pgMar subcells ผิด format (READ1_DEF แทน READ2_DEF) → `GetPointer` อ่านค่า len ~67M → bare `throw;` → `std::terminate()` | แก้ให้อ่าน subcells ด้วย READ2_DEF format |
| `GetPosition`/`SetPosition` ไม่มีใน CBinaryFileReader | ใช้ API ผิด | เปลี่ยนเป็น `GetPos()` + `Seek()` |
| คำสั้นๆ เช่น "และ" อยู่คนเดียวบรรทัด | C++ skip JS breaks แต่ `m_dThaiAccumWidthPt` ไม่ reset → accumulate ข้ามบรรทัด → overflow เร็วเกินไป | เปลี่ยนจาก skip → pass through + reset accumulator |
| Width overcount ~56pt/บรรทัด | Thai combining marks (สระ/วรรณยุกต์) IFontManager คืน non-zero advance | `IsThaiCombining()` filter ใน `MeasureWordWidthPt` |
| Break positions ผิดสำหรับ off-screen paragraphs | `m_dThaiAccumWidthPt` reset ต่อ run แทนที่จะเป็น per-paragraph | เปลี่ยนเป็น member variable, reset เฉพาะ paragraph start |
| หน้ากระดาษ hardcoded (A4 1-inch margin) | `m_dPageTextWidthPt = 159.2mm` ไม่อ้างอิง page setup จริง | `PreScanForPageDimensions()` อ่าน sectPr ก่อน pass หลัก |
| "และ" หลุดไปบรรทัดตัวเอง (ตามด้วย JS break → 3 บรรทัด) | `i=0` ของ run ไม่มี overflow check → space ท้าย " ๆ " พองใน accumulator → cross-run false overflow ไม่ถูก detect | เพิ่ม cross-run overflow check ที่ `i=0` + `m_nThaiPendingCppBreaks` balance ดูด JS break ส่วนเกิน + trim trailing spaces จาก sAccum ก่อน flush |

---

### Dictionary

**Source:** `config/dictionary/words_th.txt` (62,102 entries)  
**Format:** UTF-8, one word per line  
**Install paths ใน container:**
1. `/var/www/onlyoffice/documentserver/dictionary/words_th.txt` (primary)
2. `/var/www/onlyoffice/documentserver/server/FileConverter/bin/dictionary/words_th.txt`

Dictionary เดียวกันกับที่ JS ใช้ใน `ThaiDictionary.js`  
Lazy-initialized ครั้งเดียว (`std::call_once`) — thread-safe

---

## ดูเพิ่มเติม

- [thaiDistributed.md](thaiDistributed.md) — Thai Distributed feature overview (JS + C++)
- `core/OOXML/Common/SimpleTypes_Word.h` — `jcThaiDistribute = 9`
- `core/OOXML/Binary/Document/BinWriter/BinaryWriterD.cpp` — write side
- `core/OOXML/Binary/Document/BinReader/BinaryReaderD.cpp` — read side
- `core/OOXML/Binary/Presentation/BinaryFileReaderWriter.h` — `CBinaryFileReader` API
