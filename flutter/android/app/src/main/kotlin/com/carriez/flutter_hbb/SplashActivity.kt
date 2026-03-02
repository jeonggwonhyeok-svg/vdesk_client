package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.ImageView

class SplashActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 전체 화면 모드
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        )

        // 전체 화면 이미지를 보여주는 ImageView 설정
        val imageView = ImageView(this)
        imageView.setImageResource(R.drawable.splash_screen)
        imageView.scaleType = ImageView.ScaleType.FIT_XY
        setContentView(imageView)

        // 1.5초 후 MainActivity로 전환
        Handler(Looper.getMainLooper()).postDelayed({
            startActivity(Intent(this, MainActivity::class.java))
            finish()
        }, 1500)
    }
}
