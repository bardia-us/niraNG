<?php
declare(strict_types=1);
if (!isset($authenticated) || $authenticated !== true || !isset($auth) || !($auth instanceof NiraAdminAuth) || !$auth->authenticated()) {
    http_response_code(404);
    exit;
}
?>
<section class="card" id="feedback">
<div class="row"><h2>Feedback inbox · <?= $feedbackUnread ?> unread</h2><a href="index.php?feedback_filter=unread#feedback">Unread</a><a href="index.php#feedback">All reports</a></div>
<p>Reports are retained for 90 days, up to 100 per device and 5000 total. Opening a report leaves it unread until you mark it as read. Attached configuration may contain server credentials; copy and share it with care.</p>
<?php if ($feedbackDetail !== null):
    $identity = json_decode($feedbackDetail['identity_json'], true, 16, JSON_THROW_ON_ERROR);
    $copy = "Report: " . $feedbackDetail['report_id'] . "\nReceived: " . gmdate('c', (int)$feedbackDetail['created_at']) . "\n\nRegistered device:\n"
        . json_encode($identity, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR)
        . "\n\nMessage:\n" . $feedbackDetail['message'];
    foreach (['ui_metrics_json' => 'Flutter UI performance (20 second capture)', 'diagnostics_json' => 'Diagnostics', 'selected_server_json' => 'Selected server'] as $field => $label) {
        if ($feedbackDetail[$field] !== null) $copy .= "\n\n" . $label . ":\n" . json_encode(json_decode($feedbackDetail[$field], true, 16, JSON_THROW_ON_ERROR), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }
    if ($feedbackDetail['selected_config'] !== null) $copy .= "\n\nSelected configuration (attached by sender):\n" . $feedbackDetail['selected_config'];
?>
<div class="card"><div class="row"><strong>Report #<?= (int)$feedbackDetail['id'] ?></strong><span class="badge <?= $feedbackDetail['read_at'] === null ? 'reinstall' : 'unknown' ?>"><?= $feedbackDetail['read_at'] === null ? 'Unread' : 'Read' ?></span><button type="button" id="copy-feedback">Copy report</button><span id="feedback-copy-status" role="status"></span></div>
<textarea id="feedback-copy-text" class="feedback-text" readonly dir="auto" aria-label="Complete feedback report"><?= e($copy) ?></textarea>
<?php if ($feedbackDetail['selected_config'] !== null): ?><label for="feedback-config-text">Selected configuration</label><button type="button" id="copy-feedback-config" class="secondary">Copy configuration</button><textarea id="feedback-config-text" class="feedback-text" readonly dir="ltr" aria-label="Attached selected configuration"><?= e($feedbackDetail['selected_config']) ?></textarea><?php endif; ?>
<?php if ($feedbackDetail['read_at'] === null): ?><form method="post" action="index.php?feedback_id=<?= (int)$feedbackDetail['id'] ?>#feedback"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="feedback_read"><input type="hidden" name="feedback_id" value="<?= (int)$feedbackDetail['id'] ?>"><button>Mark as read</button></form><?php endif; ?></div>
<?php endif; ?>
<div class="table-wrap"><table class="feedback-list"><thead><tr><th>Status / received</th><th>Registered device</th><th>Message</th><th>Open</th></tr></thead><tbody>
<?php foreach ($feedbackRows as $feedbackRow): $identity = json_decode($feedbackRow['identity_json'], true, 16, JSON_THROW_ON_ERROR); ?>
<tr class="<?= $feedbackRow['read_at'] === null ? 'feedback-unread' : '' ?>"><td><span class="badge <?= $feedbackRow['read_at'] === null ? 'reinstall' : 'unknown' ?>"><?= $feedbackRow['read_at'] === null ? 'Unread' : 'Read' ?></span><br><?= e(display_timestamp(gmdate('c', (int)$feedbackRow['created_at']), $displayTimezone)) ?></td>
<td><?= e((string)($identity['device_name'] ?? 'Unknown device')) ?><br><small><?= e((string)($identity['app_name'] ?? '') . ' ' . (string)($identity['app_version'] ?? '')) ?> · build <?= (int)($identity['app_build'] ?? 0) ?></small></td>
<td class="feedback-preview" dir="auto"><?= e($feedbackRow['message'] !== '' ? $feedbackRow['message'] : '(Attached measurements only)') ?><?php if ((int)$feedbackRow['has_ui_metrics'] === 1): ?><br><small>Flutter UI metrics attached</small><?php endif; ?><?php if ((int)$feedbackRow['has_config'] === 1): ?><br><small>Configuration attached</small><?php endif; ?></td>
<td><a href="index.php?feedback_id=<?= (int)$feedbackRow['id'] ?>#feedback">View / copy #<?= (int)$feedbackRow['id'] ?></a></td></tr>
<?php endforeach; ?>
<?php if ($feedbackRows === []): ?><tr><td colspan="4">No <?= $feedbackOnlyUnread ? 'unread ' : '' ?>reports.</td></tr><?php endif; ?>
</tbody></table></div>
<?php if (count($feedbackRows) === 50): $last = $feedbackRows[count($feedbackRows) - 1]; ?><p><a href="index.php?feedback_before=<?= (int)$last['id'] ?><?= $feedbackOnlyUnread ? '&amp;feedback_filter=unread' : '' ?>#feedback">Older reports</a></p><?php endif; ?>
</section>
<script nonce="<?= e($nonce) ?>">
(() => {
  const status = document.getElementById('feedback-copy-status');
  async function copy(buttonId, textId) {
    const button = document.getElementById(buttonId), text = document.getElementById(textId);
    if (!button || !text) return;
    button.addEventListener('click', async () => {
      text.focus(); text.select();
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) await navigator.clipboard.writeText(text.value);
        else if (!document.execCommand('copy')) throw new Error('copy unavailable');
        status.textContent = 'Copied.';
      } catch (_) { status.textContent = 'Text selected. Press Ctrl+C / Copy.'; }
    });
  }
  copy('copy-feedback', 'feedback-copy-text');
  copy('copy-feedback-config', 'feedback-config-text');
})();
</script>
