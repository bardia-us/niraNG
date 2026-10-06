package dev.nirang.client.settings

/** Two invitations total; completing the first cannot queue both in one launch. */
object TelegramReminderPolicy {
    fun stage(firstCompleted: Boolean, secondShown: Boolean, firstSession: String, session: String): String = when {
        secondShown -> "none"
        !firstCompleted -> "first"
        firstSession == session -> "none"
        else -> "second" // Legacy joined installations have no firstSession.
    }
}
