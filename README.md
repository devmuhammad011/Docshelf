# DocShelf

DocShelf is an offline Flutter document reader for Android and iOS. Pick a local file to open it in the app. Recently opened files remain available during the current session.

| Format | Reader |
| --- | --- |
| PDF | Scrollable PDF pages with zoom |
| DOCX | Paragraph text, inline images and basic tables |
| XLSX | Sheet selection and cell values |
| PPTX | Slide selection with extracted text and embedded images |
| TXT | Selectable UTF-8 text |
| CSV | Scrollable table with selectable values |

Office previews extract readable content. They do not reproduce the original page layout, fonts, charts, animations, or formula recalculation. The legacy DOC, XLS and PPT formats are not supported.

## Run locally

Use the stable Flutter SDK with the Android or iOS toolchain, then run:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```
