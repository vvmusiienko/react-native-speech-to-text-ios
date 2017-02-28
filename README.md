![alt tag](https://github.com/muhaos/react-native-speech-to-text-ios/blob/master/baner.png)

# react-native-speech-to-text-ios [![npm version](https://img.shields.io/npm/v/react-native-maps.svg?style=flat)](https://www.npmjs.com/package/react-native-speech-to-text-ios)

React Native speech recognition component for iOS 10+

## Getting started

`$ npm install react-native-speech-to-text-ios --save`

### Mostly automatic installation

`$ react-native link react-native-speech-to-text-ios`

## Usage

```js

var SpeechToText = require('react-native-speech-to-text-ios');

...

this.subscription = NativeAppEventEmitter.addListener(
  'SpeechToText',
  (result) => {

    if (result.error) {
      alert(JSON.stringify(result.error));
    } else {
      console.log(result.bestTranscription.formattedString);
    }
	
  }
);

SpeechToText.startRecognition("en-US");

...

componentWillUnmount() {
  if (this.subscription != null) {
    this.subscription.remove();
    this.subscription = null;
  }
}

```

To stop recording call `SpeechToText.finishRecognition()` but after that you can continue to receive even with final recognition results. The events will not arrive after `result.isFinal == true`.
Call `SpeechToText.stopRecognition()` to cancel current recognition task.
The `result` objects reflects Apple `SFSpeechRecognitionResult` class.

Use this link to reference error codes https://developer.nuance.com/public/Help/DragonMobileSDKReference_iOS/Error-codes.html
