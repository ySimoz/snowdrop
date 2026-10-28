package com.snowdrop.app

import android.app.Application
import com.snowdrop.app.core.SnowdropCoreBridge

class SnowdropApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        SnowdropCoreBridge.init(this)
    }
}
