# 21 — UI reference

Vanilla HTML + CSS. Rewrite may use any toolkit; **ids and behaviours** below are the functional contract. **298 element ids** in `src/index.html` — complete roster at the end.

## Shell

- Sidebar 270 px: logo `./assets/ICCery-logo.svg`, settings/about icon buttons, preset select, media recipe select + Capture/Manage, Calibrate Printer, View Gamut, Spot Read, cal status chip, stepper 1–5.
- Main: notification banner, one visible `.stage`.
- Window 1280×800, min 1100×700, hidden until paint, dark `#1A1A22`.

Sidebar chrome ids: `openSettingsBtn`, `openAboutBtn`, `btnSavePresetModal`, `btnOpenPresetsDialog`, `presetSelect`, `mediaSelect`, `mediaRecipeStale`, `btnMediaLibraryCapture`, `btnMediaLibraryManage`, `btnCalibratePrinter`, `btnSpotRead`, `calStatusChip`.

Banner: `wizardNotification`, `wizardNotificationIcon`, `wizardNotificationText`, `wizardNotificationClose`. Auto-hides via `wizardState.noticeTimer`.

## Design tokens (`main.css`)

```
--bg-color: #1e1e1e
--panel-color: #252526
--text-color: #d4d4d4
--accent-color: #007acc
--border-color: #333333
--btn-height-sm/md/lg: 28 / 36 / 40 px
--btn-radius-sm/md: 4 / 6 px
```

Button classes: `.btn-sm` 28px, `.btn-md` 36px, `.btn-lg` 40px primary stage actions, `.btn-icon-sq` 36×36, `.icon-btn` 28×28 header, `.btn-properties` 36px. Action rows: `.stage-actions`, `.modal-actions`, `.chartread-actions`, `.print-actions-row`, `.btn-row`, `.btn-row-sm`, `.btn-row-end`, `.input-row-sm`. No ad-hoc inline heights (#177).

Help mode: `.has-tooltip` + `.tooltip-text`. Tooltips must overlay (fixed/absolute) so they do not expand document flow (#171).

Process logs: `<details class="log-container">` expandable (#54), wrapping text (#21). All logs share one CSS class — never per-stage IDs.

## Stage 0 ids

`stage-cal`, `calApplyToggleDash`, `calRgbHint`, `calSteps`, `calInkExplore`, `calNeutralEmphasis`, `btnCalGenerate`, `btnCalLayout`, `btnCalMeasure`, `calCurrentFile`, `btnCalLoad`, `btnCalLibrary`, `btnCalClear`, `calSavedSelect`, `btnCalCompute`, `calCurveSvg`, `calCurveLegend`, `calTacValue`, `calTacOverride`, `calInkLimitControls`, `calRecommendedPower`, `btnCalBackToWizard`, `calLogContainer`, `calLog`.

Collision: `calCollisionDialog`, `calCollisionMessage`, `calOverwriteBtn`, `calRenameBtn`, `calCancelCollisionBtn`.

## Stage 1 ids

`btnToggleAllHelp`, `calStage1Recommend`, `btnCalRecalibrate`, `stage1FormContainer`, radios `name="colourSpace"` (no element id on each radio), `patchCountPreset`, `patchCountCustom`, `whitePatches`, `blackPatches`, `btn-import-dataset`, `btnOpenExisting`, `targetBasename`, `btnBrowse`, `selectedPathDisplay`, `targenAdvancedDetails`, `targenPrecondProfile`, `btnBrowsePrecondProfile`, `targenNeutralSteps`, `targenNeutralConcentration`, `targenNeutralConcVal`, `targenGreySteps`, `targenSingleChannelSteps`, `targenAdaptation`, `targenAdaptationVal`, `targenDarkEmphasis`, `targenDarkEmphasisVal`, `targenDevicePower`, `targenInkLimitGroup`, `targenInkLimit`, `targenAlgorithm`, `targenHighQuality`, `btnGenerate`, `targenLogContainer`, `targenLog`.

## Stage 2 ids

`cmWarningBanner`, `instrumentSelect`, `pageSizeSelect`, `customPageSizeRow`, `customPageW`, `customPageH`, `tiffDpi`, `printtargLayoutOrder`, `printtargCustomSeedGroup`, `printtargCustomSeed`, `btnToggleLabelEdit`, `targetMetadataPrinter`, `targetMetadataInkSet`, `targetMetadataDriverPaper`, `targetMetadataActualPaper`, `targetLabelPreview`, `btnCreateLayout`, `printtargLogContainer`, `printtargLog`, `tiffGallery`, `galleryInfo`, `galleryGrid`, `rawPrintPanel`, `printNotification`, `printNotificationIcon`, `printNotificationText`, `printerSelect`, `btnRefreshPrinters`, `btnPrinterProperties`, `printerStatusBadge`, `cupsOptionsGroup`, `chkPpdFallback`, `printerTraySelect`, `mediaTypeGroup`, `printerMediaTypeSelect`, `btnOrientPortrait`, `btnOrientLandscape`, `btnPrintAll`, `btnAdvanceToStage3`.

`#cupsOptionsGroup` is **hidden on Windows** (#48). `#chkPpdFallback` is Linux-only ColorModel=Gray + cm-calibration.

## Stage 3 ids

`stage3LoadedTargetBanner`, `stage3TargetBasename`, `stage3TargetMeta`, `stage3TargetBadge`, `chartreadInstrumentSelect`, `btnDetectInstruments`, `xyTableHint`, `xyTablePanel`, `xyTableActiveStepBadge`, `xyStepPlace`, `xyStepAlign`, `xyStepScan`, `xyStepRemove`, `chartreadState`, `chartreadPrompt`, `btnStartRead`, `btnCalibrate`, `btnDoneRead`, `btnAccept`, `btnRetry`, `btnUndo`, `btnSkip`, `btnCancel`, `readProgressContainer`, `readProgress`, `readProgressText`, `readStats`, `swatchGrid`, `chartreadAveragingPanel`, `passCounterBadge`, `passesList`, `btnMeasureAnotherSheet`, `btnFinishAndAverage`, `chartreadLogContainer`, `chartreadLog`.

Button labels by state — see [15](15-stage3-chartread.md). XY stepper badges light in order Place → Align → Scan → Remove.

## Stage 4 ids

`colprofQuality`, `colprofDescription`, `colprofCopyright`, `colprofAlgorithm`, `colprofFwa`, `colprofCustomSpRow`, `colprofCustomSpPath`, `btnBrowseCustomSp`, `colprofIlluminant`, `colprofObserver`, `colprofInputViewCond`, `colprofOutputViewCond`, `btnCreateProfile`, `colprofSpinnerContainer`, `colprofStageLabel`, `colprofSuccessCard`, `colprofSuccessInfo`, `btnGoToVerify`, `colprofLogContainer`, `colprofLog`.

## Stage 5 ids

`btnVerify`, `btnInstallProfile`, `profcheckReportCard`, `profcheckBadge`, `profcheckAvgDe`, `profcheckMaxDe`, `profcheckRmsDe`, `driftHistorySection`, `driftAlertCard`, `driftAlertIcon`, `driftAlertText`, `btnDriftRecalibrate`, `driftFilterRow`, `driftPrinterFilter`, `driftChartWrap`, `driftTrendChart`, `driftEmptyState`, `verificationHistoryTable`, `verificationHistoryTbody`, `btnExportHistoryCsv`, `btnClearHistory`, `gamutViewerWrap`, `gamutViewerContainer`, `gamutControlsPanel`, `chkProfileGamut`, `rngProfileOpacity`, `chkSrgbReference`, `rngSrgbOpacity`, `chkLabAxes`, `rngAxisOpacity`, `btnGamutResetCamera`, `profcheckLogContainer`, `profcheckLog`.

Keyboard: **R** resets gamut camera when Stage 5 is visible. Bind to a focusable container (`tabindex`) so it works without clicking the canvas.

## Modals

| Dialog | Root id | Controls |
|--------|---------|----------|
| Settings | `settingsDialog` | listed in [22](22-settings-presets.md) |
| About | `aboutDialog` | `aboutVersion`, `aboutBuildDate` from `get_app_info`, `closeAboutBtn` |
| Save preset | `savePresetDialog` | `savePresetName`, `savePresetDesc`, `btnConfirmSavePreset`, `btnCloseSavePresetDialog` |
| Manage presets | `managePresetsDialog` | `managePresetsList`, `btnExportActivePreset`, `btnImportPreset`, `btnCloseManagePresetsDialog` |
| Save media recipe | `saveMediaRecipeDialog` | `saveMediaName`, `saveMediaNotes`, `saveMediaPaper`, `saveMediaInk`, `saveMediaPrinter`, `saveMediaPreset`, `saveMediaColourSpace`, `saveMediaCal`, `saveMediaApplyCal`, `btnConfirmSaveMedia`, `btnCloseSaveMediaDialog` |
| Manage media recipes | `manageMediaDialog` | `mediaLibraryList`, `mediaLibraryEmpty`, `mediaRow-{id}`, `btnMediaLibraryApply-{id}`, `btnMediaLibraryDelete-{id}`, `btnMediaLibraryApply`, `btnMediaLibraryCaptureFromManage`, `btnCloseManageMediaDialog` |
| Cal collision | `calCollisionDialog` | Overwrite / Rename / Cancel |
| Profile install collision | `profileInstallCollisionDialog` | `profileInstallCollisionMessage`, `profileOverwriteBtn`, `profileRenameBtn`, `profileCancelCollisionBtn` |
| Spot read | `spotReadView` | `btnSpotDetectInstruments`, `spotDetectError`, `spotInstrumentSelect`, `spotDefaultMissing`, `spotSetDefault`, `spotXYHint`, `spotPrompt`, `spotLastError`, `spotLogContainer`, `spotLog`, `btnSpotStart`, `btnSpotCalibrate`, `btnSpotTrigger`, `btnSpotStop`, `spotLastSample`, `spotLastEmpty`, `spotLabL`, `spotLabA`, `spotLabB`, `spotXYZ`, `spotSwatch`, `spotDeltaE`, `spotLastInstrument`, `spotLabImplausible`, `spotHistoryTable`, `spotHistoryEmpty`, `spotHistoryRow-{uuid}`, `btnSpotCopyLab`, `btnSpotExportCsv`, `spotSidecarMissing`, `btnCloseSpotRead` |
| Gamut viewer | `gamutView` | `gamutLayer-sRGB`, `gamutLayer-profile`, `gamutLayer-compare`, `btnGamutAddCompare`, `btnGamutOpenGam`, `btnGamutOpenProfile`, `btnGamutRemoveCompare`, `btnGamutSampleTiff`, `btnResetGamutCamera`, `gamutStatusText`, `gamutNoticeText`, `gamutInspectPanel`, `gamutInspectIdle`, `gamutInspectL`, `gamutInspectA`, `gamutInspectB`, `gamutInspect-sRGB`, `gamutInspect-profile`, `gamutInspect-compare`, `gamutInspectSwatch`, `gamutInspectApprox`, `gamutLabEntryL`, `gamutLabEntryA`, `gamutLabEntryB`, `btnGamutInspectLab`, `gamutTiffPreview`, `btnCloseGamutTiffPreview`, `gamutViewerUnavailable` |

## Dialogs must go through host APIs

Tauri v2 has **no** `window.__TAURI__.dialog`. Use invoke wrappers (`select_*`). Bugs #103, #210, #211 were exactly this.

## Complete `id=` roster (330)

`openSettingsBtn`, `openAboutBtn`, `btnSavePresetModal`, `btnOpenPresetsDialog`, `presetSelect`, `btnCalibratePrinter`, `calStatusChip`, `wizardNotification`, `wizardNotificationIcon`, `wizardNotificationText`, `wizardNotificationClose`, `stage-cal`, `calApplyToggleDash`, `calRgbHint`, `calSteps`, `calInkExplore`, `calNeutralEmphasis`, `btnCalGenerate`, `btnCalLayout`, `btnCalMeasure`, `calCurrentFile`, `btnCalLoad`, `btnCalLibrary`, `btnCalClear`, `calSavedSelect`, `btnCalCompute`, `calCurveSvg`, `calCurveLegend`, `calTacValue`, `calTacOverride`, `calInkLimitControls`, `calRecommendedPower`, `btnCalBackToWizard`, `calLogContainer`, `calLog`, `stage-1`, `btnToggleAllHelp`, `calStage1Recommend`, `btnCalRecalibrate`, `stage1FormContainer`, `patchCountPreset`, `patchCountCustom`, `whitePatches`, `blackPatches`, `btn-import-dataset`, `btnOpenExisting`, `targetBasename`, `btnBrowse`, `selectedPathDisplay`, `targenAdvancedDetails`, `targenPrecondProfile`, `btnBrowsePrecondProfile`, `targenNeutralSteps`, `targenNeutralConcentration`, `targenNeutralConcVal`, `targenGreySteps`, `targenSingleChannelSteps`, `targenAdaptation`, `targenAdaptationVal`, `targenDarkEmphasis`, `targenDarkEmphasisVal`, `targenDevicePower`, `targenInkLimitGroup`, `targenInkLimit`, `targenAlgorithm`, `targenHighQuality`, `btnGenerate`, `targenLogContainer`, `targenLog`, `stage-2`, `cmWarningBanner`, `instrumentSelect`, `pageSizeSelect`, `customPageSizeRow`, `customPageW`, `customPageH`, `tiffDpi`, `printtargLayoutOrder`, `printtargCustomSeedGroup`, `printtargCustomSeed`, `btnToggleLabelEdit`, `targetMetadataPrinter`, `targetMetadataInkSet`, `targetMetadataDriverPaper`, `targetMetadataActualPaper`, `targetLabelPreview`, `btnCreateLayout`, `printtargLogContainer`, `printtargLog`, `tiffGallery`, `galleryInfo`, `galleryGrid`, `rawPrintPanel`, `printNotification`, `printNotificationIcon`, `printNotificationText`, `printerSelect`, `btnRefreshPrinters`, `btnPrinterProperties`, `printerStatusBadge`, `cupsOptionsGroup`, `chkPpdFallback`, `printerTraySelect`, `mediaTypeGroup`, `printerMediaTypeSelect`, `btnOrientPortrait`, `btnOrientLandscape`, `btnPrintAll`, `btnAdvanceToStage3`, `stage-3`, `stage3LoadedTargetBanner`, `stage3TargetBasename`, `stage3TargetMeta`, `stage3TargetBadge`, `chartreadInstrumentSelect`, `btnDetectInstruments`, `xyTableHint`, `xyTablePanel`, `xyTableActiveStepBadge`, `xyStepPlace`, `xyStepAlign`, `xyStepScan`, `xyStepRemove`, `chartreadState`, `chartreadPrompt`, `btnStartRead`, `btnCalibrate`, `btnDoneRead`, `btnAccept`, `btnRetry`, `btnUndo`, `btnSkip`, `btnCancel`, `readProgressContainer`, `readProgress`, `readProgressText`, `readStats`, `swatchGrid`, `chartreadAveragingPanel`, `passCounterBadge`, `passesList`, `btnMeasureAnotherSheet`, `btnFinishAndAverage`, `chartreadLogContainer`, `chartreadLog`, `stage-4`, `colprofQuality`, `colprofDescription`, `colprofCopyright`, `colprofAlgorithm`, `colprofFwa`, `colprofCustomSpRow`, `colprofCustomSpPath`, `btnBrowseCustomSp`, `colprofIlluminant`, `colprofObserver`, `colprofInputViewCond`, `colprofOutputViewCond`, `btnCreateProfile`, `colprofSpinnerContainer`, `colprofStageLabel`, `colprofSuccessCard`, `colprofSuccessInfo`, `btnGoToVerify`, `colprofLogContainer`, `colprofLog`, `stage-5`, `btnVerify`, `btnInstallProfile`, `profcheckReportCard`, `profcheckBadge`, `profcheckAvgDe`, `profcheckMaxDe`, `profcheckRmsDe`, `driftHistorySection`, `driftAlertCard`, `driftAlertIcon`, `driftAlertText`, `btnDriftRecalibrate`, `driftFilterRow`, `driftPrinterFilter`, `driftChartWrap`, `driftTrendChart`, `driftEmptyState`, `verificationHistoryTable`, `verificationHistoryTbody`, `btnExportHistoryCsv`, `btnClearHistory`, `gamutViewerWrap`, `gamutViewerContainer`, `gamutControlsPanel`, `chkProfileGamut`, `rngProfileOpacity`, `chkSrgbReference`, `rngSrgbOpacity`, `chkLabAxes`, `rngAxisOpacity`, `btnGamutResetCamera`, `profcheckLogContainer`, `profcheckLog`, `settingsDialog`, `argyll_binary_dir`, `default_instrument`, `enable_i1pro2_leds`, `deltaEGoodMax`, `deltaEWarningMax`, `deltaEThresholdError`, `calibrationStaleDays`, `defaultInstallLocation`, `askBeforeOverwriteProfile`, `openColorPanelAfterInstall`, `logLevelSelect`, `btnOpenLogFolder`, `btnCopyLogPath`, `btnCopyLogExcerpt`, `logPathDisplay`, `saveSettingsBtn`, `closeSettingsBtn`, `calCollisionDialog`, `calCollisionMessage`, `calOverwriteBtn`, `calRenameBtn`, `calCancelCollisionBtn`, `profileInstallCollisionDialog`, `profileInstallCollisionMessage`, `profileOverwriteBtn`, `profileRenameBtn`, `profileCancelCollisionBtn`, `aboutDialog`, `aboutVersion`, `aboutBuildDate`, `closeAboutBtn`, `savePresetDialog`, `savePresetName`, `savePresetDesc`, `btnConfirmSavePreset`, `btnCloseSavePresetDialog`, `managePresetsDialog`, `managePresetsList`, `btnExportActivePreset`, `btnImportPreset`, `btnCloseManagePresetsDialog`, `mediaSelect`, `mediaRecipeStale`, `btnMediaLibraryCapture`, `btnMediaLibraryManage`, `saveMediaRecipeDialog`, `saveMediaName`, `saveMediaNotes`, `saveMediaPaper`, `saveMediaInk`, `saveMediaPrinter`, `saveMediaPreset`, `saveMediaColourSpace`, `saveMediaCal`, `saveMediaApplyCal`, `btnConfirmSaveMedia`, `btnCloseSaveMediaDialog`, `manageMediaDialog`, `mediaLibraryList`, `mediaLibraryEmpty`, `mediaRow-{id}`, `btnMediaLibraryApply-{id}`, `btnMediaLibraryDelete-{id}`, `btnMediaLibraryApply`, `btnMediaLibraryCaptureFromManage`, `btnCloseManageMediaDialog`, `btnSpotRead`, `spotReadView`, `btnCloseSpotRead`, `spotSidecarMissing`, `btnSpotDetectInstruments`, `spotDetectError`, `spotInstrumentSelect`, `spotDefaultMissing`, `spotSetDefault`, `spotXYHint`, `spotPrompt`, `spotLastError`, `spotLogContainer`, `spotLog`, `btnSpotStart`, `btnSpotCalibrate`, `btnSpotTrigger`, `btnSpotStop`, `spotLastSample`, `spotLastEmpty`, `spotLabL`, `spotLabA`, `spotLabB`, `spotXYZ`, `spotSwatch`, `spotDeltaE`, `spotLastInstrument`, `spotLabImplausible`, `spotHistoryTable`, `spotHistoryEmpty`, `spotHistoryRow-{uuid}`, `btnSpotCopyLab`, `btnSpotExportCsv`, `btnViewGamut`, `gamutView`, `gamutStatusText`, `gamutNoticeText`, `btnResetGamutCamera`, `gamutLayer-sRGB`, `gamutLayer-profile`, `gamutLayer-compare`, `btnGamutAddCompare`, `btnGamutOpenGam`, `btnGamutOpenProfile`, `btnGamutRemoveCompare`, `btnGamutSampleTiff`, `gamutInspectPanel`, `gamutInspectIdle`, `gamutInspectL`, `gamutInspectA`, `gamutInspectB`, `gamutInspect-sRGB`, `gamutInspect-profile`, `gamutInspect-compare`, `gamutInspectSwatch`, `gamutInspectApprox`, `gamutLabEntryL`, `gamutLabEntryA`, `gamutLabEntryB`, `btnGamutInspectLab`, `gamutTiffPreview`, `btnCloseGamutTiffPreview`, `gamutViewerUnavailable`.
