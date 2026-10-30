package dev.nirang.client.logs
import android.content.Context
object SafeLog {
    fun info(context: Context, message: String) {}
    fun warning(context: Context, message: String) {}
    fun error(context: Context, message: String) {}
}
