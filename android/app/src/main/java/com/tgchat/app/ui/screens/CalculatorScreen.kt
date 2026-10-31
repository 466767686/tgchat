package com.tgchat.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel

/**
 * 伪装成计算器的锁屏。输入解锁密码后按 "=" 进入聊天。
 */
@Composable
fun CalculatorScreen(vm: AppViewModel) {
    var display by remember { mutableStateOf("0") }
    var accumulator by remember { mutableStateOf<Double?>(null) }
    var pending by remember { mutableStateOf<String?>(null) }
    var resetOnNextDigit by remember { mutableStateOf(false) }

    fun compute(op: String, left: Double, right: Double): Double = when (op) {
        "+" -> left + right
        "−" -> left - right
        "×" -> left * right
        "÷" -> if (right == 0.0) Double.NaN else left / right
        else -> right
    }

    fun format(value: Double): String {
        if (value.isNaN() || value.isInfinite()) return "错误"
        return if (value == Math.floor(value) && Math.abs(value) < 1e12) {
            value.toLong().toString()
        } else {
            val text = "%.8g".format(value)
            if (text.endsWith(".0")) text.dropLast(2) else text
        }
    }

    fun press(label: String) {
        when (label) {
            "AC" -> {
                display = "0"
                accumulator = null
                pending = null
                resetOnNextDigit = false
            }
            "±" -> {
                display = if (display.startsWith("-")) display.drop(1)
                else if (display != "0") "-$display" else display
            }
            "%" -> display.toDoubleOrNull()?.let { display = format(it / 100) }
            "=" -> {
                if (display == vm.unlockPin) {
                    vm.unlock()
                } else {
                    val op = pending
                    val left = accumulator
                    val right = display.toDoubleOrNull()
                    if (op != null && left != null && right != null) {
                        val result = compute(op, left, right)
                        display = format(result)
                        accumulator = null
                        pending = null
                    }
                    resetOnNextDigit = true
                }
            }
            "+", "−", "×", "÷" -> {
                val op = pending
                val left = accumulator
                val right = display.toDoubleOrNull()
                if (op != null && left != null && right != null) {
                    val result = compute(op, left, right)
                    display = format(result)
                    accumulator = result
                } else {
                    accumulator = right
                }
                pending = label
                resetOnNextDigit = true
            }
            "." -> {
                if (resetOnNextDigit) {
                    display = "0."
                    resetOnNextDigit = false
                } else if (!display.contains(".")) {
                    display += "."
                }
            }
            else -> {
                if (resetOnNextDigit || display == "0") {
                    display = label
                    resetOnNextDigit = false
                } else if (display.length < 12) {
                    display += label
                }
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 18.dp),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.weight(0.35f))
            Text(
                text = display,
                color = Color.White,
                fontSize = 72.sp,
                fontWeight = FontWeight.Light,
                textAlign = TextAlign.End,
                maxLines = 1,
                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
            )

            val rows = listOf(
                listOf("AC", "±", "%", "÷"),
                listOf("7", "8", "9", "×"),
                listOf("4", "5", "6", "−"),
                listOf("1", "2", "3", "+"),
            )
            for (row in rows) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    for (label in row) {
                        CalculatorKey(
                            label = label,
                            kind = kindOf(label),
                            modifier = Modifier.weight(1f),
                            onClick = { press(label) },
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                CalculatorKey("0", KeyKind.DIGIT, Modifier.weight(2f)) { press("0") }
                CalculatorKey(".", KeyKind.DIGIT, Modifier.weight(1f)) { press(".") }
                CalculatorKey("=", KeyKind.OP, Modifier.weight(1f)) { press("=") }
            }
            Spacer(Modifier.weight(0.2f))
        }
    }
}

private enum class KeyKind { DIGIT, FUNCTION, OP }

private fun kindOf(label: String): KeyKind = when (label) {
    "÷", "×", "−", "+", "=" -> KeyKind.OP
    "AC", "±", "%" -> KeyKind.FUNCTION
    else -> KeyKind.DIGIT
}

@Composable
private fun CalculatorKey(
    label: String,
    kind: KeyKind,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val background = when (kind) {
        KeyKind.DIGIT -> Color(0xFF333333)
        KeyKind.FUNCTION -> Color(0xFFA5A5A5)
        KeyKind.OP -> Color(0xFFFF9F0A)
    }
    val textColor = if (kind == KeyKind.FUNCTION) Color.Black else Color.White

    Box(
        modifier = modifier
            .height(70.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(background)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = label, color = textColor, fontSize = 28.sp)
    }
}
