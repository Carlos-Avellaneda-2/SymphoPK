package com.carlosavellaneda.symphopk

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity reutiliza el FlutterEngine del servicio de audio, de
// modo que la UI se reconecta a la reproducción en curso al reabrir la app.
class MainActivity : AudioServiceActivity()
