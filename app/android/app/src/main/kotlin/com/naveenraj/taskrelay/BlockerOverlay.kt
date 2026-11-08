package com.naveenraj.taskrelay

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * The block screen: one full-screen window of type TYPE_ACCESSIBILITY_OVERLAY, which only an enabled accessibility service may add
 * and which needs no permission of its own (no SYSTEM_ALERT_WINDOW). Built in code (no layout file) and STRICTLY black and white:
 * a pure black background, white and grey text, a white primary button with black text, outlined secondary buttons.
 *
 * Window flags: FLAG_NOT_FOCUSABLE, so it never takes key focus (the keyboard and the Back key keep working for whatever is
 * underneath) while still receiving the touches on its buttons; it covers the whole screen, display cutouts included.
 * Main thread only. [show] may be called again while visible: it just refreshes the texts.
 */
class BlockerOverlay(private val service: AccessibilityService, private val actions: Actions) {

    interface Actions {
        fun onOpenApp()
        fun onCheckAgain()
        fun onClose()
    }

    private class Views(val root: View, val reason: TextView, val next: TextView, val status: TextView, val headline: TextView, val check: Button)

    private var views: Views? = null
    private var attached = false
    private var checking = false

    val isShowing: Boolean get() = attached

    /** Adds the window (or refreshes it when it is already up). Never throws: a refused window just means no overlay. */
    fun show(screen: BlockScreen) {
        try {
            val v = views ?: build().also { views = it }
            bind(v, screen)
            if (!attached) {
                (service.getSystemService(Context.WINDOW_SERVICE) as WindowManager).addView(v.root, windowParams())
                attached = true
            }
        } catch (t: Throwable) {
            Log.w(TAG, "block screen not shown: ${t.javaClass.simpleName}")
            attached = false
            views = null
        }
    }

    fun dismiss() {
        val v = views
        if (attached && v != null) {
            try {
                (service.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeViewImmediate(v.root)
            } catch (t: Throwable) {
                Log.w(TAG, "block screen not removed: ${t.javaClass.simpleName}")
            }
        }
        attached = false
        views = null
        checking = false
    }

    /** "Checking..." on the Check again button while a sync runs. */
    fun setChecking(on: Boolean) {
        checking = on
        views?.let { applyChecking(it) }
    }

    /** A small grey line under the buttons (the result of a check); null hides it. */
    fun setStatus(text: String?) {
        val s = views?.status ?: return
        s.text = text.orEmpty()
        s.visibility = if (text.isNullOrEmpty()) View.GONE else View.VISIBLE
    }

    // ── building ─────────────────────────────────────────────────────────────────────────────────────────────────

    private fun bind(v: Views, screen: BlockScreen) {
        v.headline.text = screen.headline
        v.reason.text = screen.reason
        v.reason.visibility = if (screen.reason.isEmpty()) View.GONE else View.VISIBLE
        v.next.text = screen.next.orEmpty()
        v.next.visibility = if (screen.next == null) View.GONE else View.VISIBLE
        v.check.visibility = if (screen.canCheckAgain) View.VISIBLE else View.GONE
        applyChecking(v)
    }

    private fun applyChecking(v: Views) {
        v.check.isEnabled = !checking
        v.check.text = if (checking) BlockerText.CHECKING else BlockerText.CHECK_AGAIN
        v.check.contentDescription = if (checking) "Checking" else "Check again for changes"
    }

    private fun build(): Views {
        val ctx: Context = service
        val brand = label(ctx, "TASKRELAY", 12f, GREY).apply {
            letterSpacing = 0.2f
            typeface = Typeface.DEFAULT_BOLD
        }
        val headline = label(ctx, "", 28f, WHITE).apply {
            typeface = Typeface.DEFAULT_BOLD
            ViewCompat.setAccessibilityHeading(this, true)
        }
        val reason = label(ctx, "", 18f, GREY_LIGHT)
        val next = label(ctx, "", 15f, GREY)
        val open = button(ctx, BlockerText.OPEN_APP, "Open the TaskRelay app", primary = true) { actions.onOpenApp() }
        val check = button(ctx, BlockerText.CHECK_AGAIN, "Check again for changes", primary = false) { actions.onCheckAgain() }
        val close = button(ctx, BlockerText.CLOSE, "Close the block screen", primary = false) { actions.onClose() }
        val status = label(ctx, "", 13f, GREY).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.GONE
        }

        val column = CappedColumn(ctx, dp(480f)).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(28f), dp(48f), dp(28f), dp(48f))
            addView(brand)
            addView(headline, below(12f))
            addView(reason, below(14f))
            addView(next, below(8f))
            addView(open, below(32f))
            addView(check, below(12f))
            addView(close, below(12f))
            addView(status, below(14f))
        }
        val scroll = ScrollView(ctx).apply {
            isFillViewport = true // short content is centred, long content (large font, landscape) scrolls
            overScrollMode = View.OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
            addView(column, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
        }
        val root = FrameLayout(ctx).apply {
            setBackgroundColor(BLACK)
            // Swallow every touch that no button took: nothing underneath is reachable. (A touch listener, not isClickable, so
            // TalkBack does not announce the whole screen as one big button.)
            setOnTouchListener { _, _ -> true }
            addView(scroll, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        // The window covers the system bars; keep the content clear of them (zero where Android reports none).
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            scroll.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        return Views(root, reason, next, status, headline, check)
    }

    private fun windowParams(): WindowManager.LayoutParams =
        WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

    private fun label(ctx: Context, text: String, sp: Float, color: Int) = TextView(ctx).apply {
        this.text = text
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp) // sp: follows the user's font size
        setTextColor(color)
    }

    private fun button(ctx: Context, text: String, description: String, primary: Boolean, onClick: () -> Unit) = Button(ctx).apply {
        this.text = text
        contentDescription = description
        isAllCaps = false
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(if (primary) BLACK else WHITE)
        minHeight = dp(52f)
        minimumHeight = dp(52f)
        stateListAnimator = null // no elevation shadow: it would be a grey smudge on black
        background = RippleDrawable(ColorStateList.valueOf(RIPPLE), shape(if (primary) WHITE else Color.TRANSPARENT, outline = !primary), shape(WHITE, outline = false))
        setOnClickListener { onClick() }
    }

    private fun shape(fill: Int, outline: Boolean) = GradientDrawable().apply {
        setColor(fill)
        cornerRadius = dp(14f).toFloat()
        if (outline) setStroke(dp(1.5f), OUTLINE)
    }

    /** Full-width layout params with a [gap] (dp) above. */
    private fun below(gap: Float) = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(gap) }

    private fun dp(v: Float): Int = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, service.resources.displayMetrics).toInt()

    /** A vertical column that never gets wider than [maxPx] (tablets, landscape): it is centred by its FrameLayout parent. */
    private class CappedColumn(ctx: Context, private val maxPx: Int) : LinearLayout(ctx) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val w = MeasureSpec.getSize(widthMeasureSpec)
            val capped = if (w > maxPx) MeasureSpec.makeMeasureSpec(maxPx, MeasureSpec.EXACTLY) else widthMeasureSpec
            super.onMeasure(capped, heightMeasureSpec)
        }
    }

    companion object {
        private const val TAG = "BlockerOverlay"

        // Black, white and greys only: the whole app is monochrome.
        private const val BLACK = 0xFF000000.toInt()
        private const val WHITE = 0xFFFFFFFF.toInt()
        private const val GREY_LIGHT = 0xFFD0D0D0.toInt()
        private const val GREY = 0xFF9A9A9A.toInt()
        private const val OUTLINE = 0xFFBDBDBD.toInt()
        private const val RIPPLE = 0x55808080
    }
}
