# Thai Distributed Alignment (`w:jc thaiDistribute`)

การทำ Thai Distributed Alignment สำหรับ ONLYOFFICE Document Editor ใน edoc-office แบ่งออกเป็น 2 ส่วนหลัก:

---

## 1. Client-Side (sdkjs) — Word Editor & Download As

`sdkjs` คือ JavaScript layer ที่ทำงานฝั่ง browser และฝั่ง `doctrenderer` (Node.js) ตอน export เอกสาร  
ใช้สำหรับ: แสดงผลใน Word Editor, และ "Download As" (PDF/DOCX จาก client-side renderer)

### ไฟล์ที่แก้ไขใน sdkjs

| ไฟล์ | สิ่งที่แก้ไข |
|------|-------------|
| `word/Editor/Paragraph_Recalculate.js` | `SegmentThaiWords`, `private_ApplyThaiDictSegmentation`, `align_Distributed` render logic, `RecalculateFastRunRange` return -1 |
| `word/Editor/Run.js` | `isBreakBefore` (disable for Thai), `isBreakAfter` (uses `IsSpaceAfter()` without fontHint), `fitOnLine` word-level logic, `Set_LineBreakPos(Pos+1)` at SpaceAfter |
| `word/Editor/Serialize2.js` | อ่าน/เขียน `align_Distributed` ใน binary format |
| `word/apiBuilder.js` | `SetJc`/`GetJc` map `"thaiDistribute"` ↔ `align_Distributed` |
| `word/fromToJSON.js` | map `"thaiDist"` → `align_Distributed` |

---

### Algorithm: Word-Level Line Wrap

#### Step 1 — Segmentation (`SegmentThaiWords`)

เรียกตอน: alignment เปลี่ยนเป็น `thaiDistribute`, หรือ recalculate paragraph

```
SegmentThaiWords()
  └─ สำหรับแต่ละ run ใน paragraph:
       1. reset SpaceAfter = false บนทุก Thai char
       2. รวบรวม Thai sequence → private_ApplyThaiDictSegmentation()
```

#### Step 2 — Dict Segmentation (`private_ApplyThaiDictSegmentation`)

ใช้ dictionary-based maximum matching จาก `ThaiDictionary.js`  
(สร้างจาก `config/dictionary/words_th.txt`)

```
ข้อความ: "การทำงาน"
→ dict match "การ" → SpaceAfter บน 'ร' (index 2)
→ dict match "ทำงาน" → SpaceAfter บน 'น' (index ท้าย)
→ ถ้าไม่ match: advance 1 char, SpaceAfter บน char สุดท้ายของ unmatched group
```

**Bug ที่แก้แล้ว:** เดิมมีเงื่อนไข `endIdx < positions.length - 1` ทำให้คำสุดท้ายของ sequence ไม่มี SpaceAfter → แก้โดยลบเงื่อนไขนั้นออก เพื่อให้ทุกคำรวมคำสุดท้ายได้ SpaceAfter

#### Step 3 — Line Breaking (ใน `protected_FillRange`, `Run.js`)

ตรรกะหลักในการตัดบรรทัด:

```
สำหรับแต่ละ character ใน run:
  ถ้า !IsSpaceAfter(char):
    fitOnLine = true  (สะสม WordLen ต่อไป ยังไม่ตัด)
  ถ้า IsSpaceAfter(char):  (= ท้ายคำ)
    fitOnLine = isFitOnLine(X, SpaceLen + WordLen + GraphemeLen)  (ตรวจจริง)
    Set_LineBreakPos(Pos+1)  (rollback target = ต้นคำถัดไป)
    ถ้า overflow → MoveToLBP → ทั้งคำไปบรรทัดถัดไป
```

**สิ่งที่แก้ไขเพิ่ม:**
- `isBreakBefore` disabled สำหรับ Thai (เดิม treat Thai char เหมือน CJK ทำให้ตัดทุก char)
- `isBreakAfter` ใช้ `IsSpaceAfter()` โดยไม่ส่ง fontHint (เดิม trigger บน ambiguous chars)
- ลบ zero-width space code สำหรับ Thai Distributed (ไม่ต้องการ)

#### Step 4 — Line Boundary Markers

หลัง recalculate, inject `CRunBreak(break_Line)` ที่ word boundaries แทน `CRunSpace`  
เหตุผล: `CRunSpace` serialize เป็น `<w:r><w:t> </w:t></w:r>` (เพิ่มช่องว่าง), แต่ `CRunBreak(break_Line)` serialize เป็น `<w:br/>` (ถูกต้อง)

#### Step 5 — Render (Distributed Spacing)

```
align_Distributed:
  ถ้าบรรทัดสุดท้าย (ParaEnd):
    left-align, JustifyWord = 0
  ถ้าไม่ใช่บรรทัดสุดท้าย:
    JustifyWord = (lineWidth - textWidth) / (nBaseLetters - 1)
    กระจาย spacing ระหว่าง base characters ทุกคู่
```

---

### Bugs ที่แก้แล้ว (ทั้งหมด)

| # | Bug | สาเหตุ | วิธีแก้ |
|---|-----|--------|---------|
| — | Thai char ถูก break ทุก char | `isBreakBefore` treat Thai เหมือน CJK | disable `isBreakBefore` สำหรับ Thai |
| — | `isBreakAfter` trigger ผิด | ส่ง fontHint → ambiguous chars | ใช้ `IsSpaceAfter()` ไม่มี fontHint |
| — | Ctrl+Z error / timer leak | `ThaiSegmentTimer` ไม่ถูก clear ก่อน recalculate | `clearTimeout(ThaiSegmentTimer)` ใน `Recalculate_Page` |
| — | alignment click ไม่ทำงาน | click ซ้ำ alignment เดิม → ไม่ trigger recalc | เพิ่ม `_prevThaiJc` + 0ms follow-up `LogicDocument.Recalculate()` |
| 11 | Character หายตอน inject | reverse inject loop ผิด + backward scan | reverse loop `nLines-2 → 0`, `insertPos = runEndPos` ตรงๆ |
| 13 | Step 1 cleanup ผิด | check `_isLineBoundarySpace` flag (เก่า) | เปลี่ยนเป็น `break_Line` type check เหมือน `private_CleanLineBoundarySpaces` |
| 14 | Mid-word break หลัง typing | `RecalculateFastRunRange` ข้าม cleanup → injected `break_Line` force new range | return `-1` สำหรับ `ThaiDistributed` เพื่อ force full `Recalculate_Page` |

---

### Build

```bash
make build   # 3-stage Docker build: cpp-builder → js-builder → final image
```

- แก้ไข source ใน `sdkjs/` ต้อง `make build` เสมอ (ไม่ใช่ hot-reload)
- Hard refresh browser หลัง rebuild: `Cmd+Shift+R`
- sdkjs ถูก bundle เป็น `sdk-all.js` / `sdk-all-min.js`

---

## 2. Server-Side (core/OOXML) — ForceSave & Converter

Server-side rendering ใช้สำหรับ:
- **ForceSave** — บันทึกเอกสารกลับเป็น DOCX จาก server (binary → DOCX via x2t)
- **Converter** — แปลงไฟล์ผ่าน `FileConverter` service

### Architecture

```
client → CoAuthoring (port 8000) → ForceSave → x2t (BinaryReaderD.cpp)
                                 → FileConverter → x2t
```

Server-side ใช้ C++ core (`core/`) ผ่าน `x2t` เท่านั้น — **ไม่ใช้ sdkjs**

### Root Cause ของ `<w:br/>` หาย

`thaiLineBreaks` logic ใน `Serialize2.js` อาศัย `par.GetLinesCount() > 1` (paragraph ต้องถูก recalculate แล้ว = อยู่ใน viewport)

**paragraphs ที่อยู่นอก viewport จะ:**
- `IsRecalculated() = false`
- `GetLinesCount() = 0`
- `thaiLineBreaks = null`
- ไม่มี `c_oSerRunType::linebreak` bytes ใน binary
- → C++ `BinaryReaderD` ไม่มีอะไรให้แปลงเป็น `<w:br/>`

**เป้าหมาย:** ForceSave และ Converter ต้องให้ผลลัพธ์ตรงกับ client-side JS เพราะถ้าตำแหน่ง `<w:br/>` ต่างกัน เอกสารจะเปิดและแสดงผลไม่ตรงกัน ทำให้ workflow ใช้งานต่อไม่ได้

---

### C++ Fix (implemented)

#### Design: Font-Metrics Line Breaking

แทนที่จะใช้ heuristic (char count) ให้คำนวณตำแหน่งตัดบรรทัดด้วย font metrics จริง เหมือนที่ JS ทำ:

```
สำหรับแต่ละ paragraph ที่มี w:jc="thaiDistribute":
  1. รู้จาก sectPr → ความกว้าง text area จริง (pageWidth - marginLeft - marginRight)
  2. รู้จาก paragraph indent → dBodyWidthPt และ dFirstLineWidthPt
  3. รู้จาก font+size → ผ่าน NSFonts::IFontManager::MeasureChar2()
  4. segment Thai text → ThaiWordBreaker (max matching dict)
  5. สะสม word widths → ถ้าเกิน effective width → emit <w:br/> + reset
```

#### ไฟล์ที่สร้าง/แก้ไข

| ไฟล์ | การเปลี่ยนแปลง |
|------|----------------|
| `BinReader/ThaiWordBreaker.h` | **NEW** Thai dictionary maximum matching class |
| `BinReader/ThaiWordBreaker.cpp` | **NEW** Implementation: load `words_th.txt`, segment Thai sequences |
| `BinReader/fontTableWriter.h` | เพิ่ม `GetFontManager()` getter เพื่อ expose `m_pFontManager` |
| `BinReader/StylesWriter.h` | เพิ่ม `m_oDocDefaultRPr` และ `m_mapStyleRPr` (styleId → rPr) |
| `BinReader/BinaryReaderD.h` | เพิ่ม `m_dPageTextWidthPt`, `m_dThaiAccumWidthPt`, `m_bThaiFirstLineDone`, `m_nThaiPendingCppBreaks`, `UpdatePageSizeFromSectPr()`, `PreScanForPageDimensions()`, `MeasureWordWidthPt(…, bFauxBold)` |
| `BinReader/BinaryReaderD.cpp` | ดู algorithm ด้านล่าง |
| `Projects/Linux/BinDocument/BinDocument.pro` | เพิ่ม `ThaiWordBreaker.cpp` |
| `Dockerfile` | copy `words_th.txt` → 2 paths (primary + next to x2t binary) |

#### Algorithm (C++ side)

```
Read():
  → PreScanForPageDimensions()   ← อ่าน sectPr ก่อน paragraph ใดๆ
  → READ_TABLE_DEF(ReadDocumentContent)  ← pass ปกติ

PreScanForPageDimensions():
  → GetPosition() → save nSavedPos
  → scan body cells: skip non-sectPr via GetPointer(len)
  → เมื่อพบ c_oSerParType::sectPr:
       อ่าน pgSz.W → dPageWidthMm
       อ่าน pgMar.Left + pgMar.Right → dLeftMm, dRightMm
       m_dPageTextWidthPt = (W - Left - Right) * 72/25.4
  → SetPosition(nSavedPos)  ← restore stream

ReadDocDefaults():
  → parse rPr → m_oStylesWriter.m_oDocDefaultRPr  (font/size fallback ระดับ document)

ReadStyleContent():
  → parse Style TextPr rPr → m_oStylesWriter.m_mapStyleRPr[styleId]

ReadParagraph(pPr):
  → ถ้า jcThaiDistribute:
       m_bIsThaiDistribute = true
       m_dThaiAccumWidthPt = 0.0      ← reset cross-run line width
       m_bThaiFirstLineDone = false   ← reset first-line state
  → ถ้า sectPr exists → UpdatePageSizeFromSectPr()  (multi-section live update)

ReadRunContent(run, text):
  if m_bIsThaiDistribute:
    WriteThaiDistributeRunText(text)
  else:
    emit <w:t>text</w:t>  (normal)

ReadRunContent(linebreak):
  if m_bIsThaiDistribute:
    ถ้า m_nThaiPendingCppBreaks > 0:
      m_nThaiPendingCppBreaks--   ← absorb JS break (C++ already broke here)
    else:
      emit <w:br/>                ← pass through JS break
    m_dThaiAccumWidthPt = 0.0
    m_bThaiFirstLineDone = true
  else:
    emit <w:br/>

WriteThaiDistributeRunText(text):
  1. Font resolution (priority order):
       run rPr → paragraph style rPr (m_mapStyleRPr) → docDefaults rPr → 12pt
     - font: m_oRFonts.m_sCs > m_sEastAsia > m_sAscii
     - size: m_oSzCs > m_oSz

  2. Effective line width:
       dBodyWidthPt  = m_dPageTextWidthPt - start_indent - end_indent
       dFirstWidthPt = dBodyWidthPt - firstLine_indent  (หรือ + hanging)
       getEffectiveWidth() = m_bThaiFirstLineDone ? dBodyWidthPt : dFirstWidthPt

  3. Load font:
       Resolve bold/italic from run rPr → style rPr → docDefaults:
         - bBold:   m_oBoldCs > m_oBold (ToBool())
         - bItalic: m_oItalicCs > m_oItalic (ToBool())
       nFontStyle = 0x01 if bBold (FontManager: 0x01=bold, 0x02=italic)
                  | 0x02 if bItalic
       IFontManager::LoadFontByName(fontName, sizePt, nFontStyle, dpiX=72, dpiY=72)
       IFontManager::AfterLoad()
       → ถ้าเจอ THSarabun Bold.ttf: ใช้ real bold advance widths
       → ถ้าไม่เจอ: FontManager ทำ faux bold อัตโนมัติ (SetNeedBold → +1/glyph ใน MeasureChar2)

  4. Segment + measure (cross-run):
       ThaiWordBreaker::Segment(text) → words[]
       for each word[i]:

         i == 0 (first word of run) — cross-run overflow check:
           width = MeasureWordWidthPt()
           ถ้า accum > 0 AND seg starts Thai AND accum + width > effectiveWidth:
             → flushAndBreak()  ← m_nThaiPendingCppBreaks++
             → m_dThaiAccumWidthPt = width
           else:
             → m_dThaiAccumWidthPt += width

         i > 0 — Thai↔Thai or space→Thai boundary check:
           prevIsBreakEnd = prev ends with Thai OR space
           curStartsThai  = seg starts with Thai
           ถ้า prevIsBreakEnd AND curStartsThai:
             width = MeasureWordWidthPt()
             ถ้า accum + width > effectiveWidth:
               → trim trailing spaces จาก sAccum (renderer ไม่ trim ให้)
               → flush sAccum as <w:t>
               → flushAndBreak()  ← m_nThaiPendingCppBreaks++
               → m_dThaiAccumWidthPt = width
             else:
               → m_dThaiAccumWidthPt += width

         sAccum += word

       end-of-run: trim trailing spaces จาก sAccum
         → ลด m_dThaiAccumWidthPt ด้วย space width ที่ trim (ป้องกัน carry-over inflation)
         → flush sAccum as <w:t>
```

#### Font Resolution Chain

```
Priority  Source                          Field
1         run rPr (m_oCur_rPr)           m_oRFonts.{m_sCs, m_sEastAsia, m_sAscii}
2         paragraph style rPr             m_mapStyleRPr[m_oCur_pPr.m_oPStyle->m_sVal]
          (จาก w:style → w:rPr)
3         document defaults               m_oDocDefaultRPr  (จาก w:docDefaults → w:rPrDefault)
4         OOXML spec default              12pt, ไม่มี font name (IFontManager เลือก fallback เอง)
```

#### Indent Handling

```
w:ind fields:
  m_oStart     → left indent  → หักจาก text width (ทุกบรรทัด)
  m_oEnd       → right indent → หักจาก text width (ทุกบรรทัด)
  m_oFirstLine → เยื้องหัวเพิ่ม → หักเพิ่มเฉพาะบรรทัดแรก (แคบลง)
  m_oHanging   → hanging indent → เพิ่มพื้นที่เฉพาะบรรทัดแรก (กว้างขึ้น)

บรรทัดแรก:  dEffectiveWidthPt = dBodyWidthPt - dFirstLineExtraPt
หลัง break: dEffectiveWidthPt = dBodyWidthPt  (switch ทันที)
```

#### Dictionary Loading

```
ThaiWordBreaker.Init() โหลด words_th.txt จาก:
  1. /var/www/onlyoffice/documentserver/dictionary/words_th.txt  (primary)
  2. /var/www/onlyoffice/documentserver/server/FileConverter/bin/dictionary/words_th.txt
  3. /etc/onlyoffice/documentserver/dictionary/words_th.txt
  4. ./dictionary/words_th.txt  (relative to CWD)
```

Lazy-initialized ครั้งเดียว (`std::call_once`) — thread-safe, ไม่กระทบ performance

#### Page Width Resolution

```
ลำดับการได้ค่า m_dPageTextWidthPt:

1. PreScanForPageDimensions() [ก่อน paragraph ใดๆ]
     → seek หา body-level sectPr ท้าย stream
     → อ่าน pgSz.W, pgMar.Left/Right (mm หรือ twips)
     → m_dPageTextWidthPt = (W - Left - Right) * 72/25.4
     → restore stream position

2. UpdatePageSizeFromSectPr() [live update ระหว่างอ่าน]
     → ถูกเรียกเมื่อพบ sectPr ใน paragraph (paragraph สุดท้ายของแต่ละ section)
     → อัปเดต m_dPageTextWidthPt ใหม่สำหรับ section ถัดไป

ตัวอย่าง:
  A4 + margin 2.54cm: (210 - 25.4 - 25.4) * 72/25.4 ≈ 453pt
  A4 + margin 1.5cm:  (210 - 15 - 15) * 72/25.4     ≈ 503pt
  Letter + margin 1in: ~470pt
```

#### ความสัมพันธ์กับ JS

**On-screen paragraphs** (`IsRecalculated=true` — paragraph อยู่ใน viewport):
- JS inject `c_oSerRunType::linebreak` ที่ขอบบรรทัดถูกต้องแล้ว (JS เห็น rendered layout จริง)
- C++ **pass through** JS breaks → emit `<w:br/>` + reset `m_dThaiAccumWidthPt = 0.0`
- JS แบ่ง text เป็น word-level runs ด้วย → C++ measure each word แต่ไม่ overflow เพราะ accumulator reset หลัง break ทุกครั้ง

**Off-screen paragraphs** (`IsRecalculated=false` — paragraph นอก viewport):
- JS ไม่ inject linebreak bytes เลย (ไม่รู้ rendered layout)
- C++ ได้ text ทั้ง paragraph ใน run เดียว → `WriteThaiDistributeRunText` segment + measure + inject `<w:br/>` เอง

**Balance counter `m_nThaiPendingCppBreaks`**:
- เมื่อ C++ insert break ก่อน JS (cross-run overflow) → `pending++`
- เมื่อ JS break มาถึง → ถ้า `pending > 0`: absorb (ไม่ emit) + `pending--`
- ป้องกันบรรทัดเกินเมื่อ C++ และ JS ต่างก็ตัดที่ตำแหน่งใกล้กัน

**Bugs ที่แก้แล้ว**:

| Bug | สาเหตุ | วิธีแก้ |
|-----|--------|---------|
| width สะสมข้ามบรรทัด → overflow เร็ว | `m_dThaiAccumWidthPt` ไม่ reset หลัง JS break | pass through JS break + reset accumulator |
| คำสั้นๆ เช่น "และ" หลุดเป็นบรรทัดเดียว | ไม่มี cross-run overflow check ที่ i=0 + trailing space inflate accumulator | เพิ่ม i=0 check + trim trailing spaces + balance counter |
| space ท้าย run พัง overflow chain | `prevIsBreakEnd` ไม่รวม `prev.back() == ' '` → space→Thai boundary ไม่ถูก detect | เพิ่ม `prev.back() == L' '` ใน boundary condition |
| bold text วัด width ผิด | `nFontStyle` bit swap (0x01=italic, 0x02=bold ผิด) | แก้เป็น 0x01=bold, 0x02=italic ตาม FontManager.cpp |

---

## Related Repositories

| Repo | Branch/Notes |
|------|-------------|
| `github.com/BlackMocca/sdkjs` | fork ที่แก้ไข JS layer |
| `github.com/BlackMocca/web-apps` | fork web-apps |
| `github.com/BlackMocca/build_tools` | fork build tools |
| `github.com/BlackMocca/core` | fork C++ core (pending Thai distributed) |

---

## Reference

- OOXML spec: `w:jc val="thaiDistribute"` — Thai paragraph alignment
- ONLYOFFICE upstream: `https://github.com/ONLYOFFICE/DocumentServer`
- Dictionary source: `config/dictionary/words_th.txt`
