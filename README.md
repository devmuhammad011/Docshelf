# DocShelf

DocShelf is an offline Flutter document reader for Android and iOS. Choose a file with **Browse files** or send it from another app. On Android, source apps can offer DocShelf under **Open with** or **Share** when they provide a supported document MIME type. On iOS, DocShelf registers as a document viewer for supported file types.

The library retains up to 20 recently opened documents as app-private copies so they can reopen later, even if the source app's temporary file is gone. **Settings** lets readers choose a light, dark or system theme, adjust reading text size in text previews, and delete the saved copies. The original files remain in their source locations. Imports accept files up to 100 MB.

| Format | Reader |
| --- | --- |
| PDF | Scrollable PDF pages with zoom |
| DOCX | Headings, paragraphs, line breaks, inline images and basic tables |
| XLSX | Sheet selection and cell values, including skipped rows and columns. Formula text is shown when no cached result is present. |
| PPTX | Slide selection with extracted text, embedded images and basic tables |
| TXT | Selectable UTF-8 text |
| CSV | Scrollable table with selectable values |

Office previews preserve readable content. Page breaks, exact slide positioning, Excel styles/charts and animations are outside the current renderer. The legacy DOC, XLS and PPT formats use different binary structures from the ZIP/XML-based Office formats. Supporting them offline would require a separate mobile reader or converter. Convert those files to DOCX, XLSX, PPTX or PDF before opening in DocShelf.

## Run locally

Use Flutter 3.50 or later with the Android or iOS toolchain.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

To build an installable Android test package:

```sh
flutter build apk --debug
```

The test package is signed for debugging. The tests include locally generated sample DOCX, XLSX and PPTX files in `test/fixtures`.
