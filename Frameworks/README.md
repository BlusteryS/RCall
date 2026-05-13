Поместите сюда `WebRTC.framework` для сборки через `RCall_EXTRA_FRAMEWORKS := WebRTC`.

Без native WebRTC framework приложение не сможет собрать звонок, потому что iOS SDK не содержит WebRTC.
