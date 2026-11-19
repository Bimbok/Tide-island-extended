.pragma library

function toSeconds(value) {
    const numberValue = Number(value);
    if (isNaN(numberValue) || numberValue <= 0) return 0;
    if (numberValue < 10000) return numberValue;
    if (numberValue < 10000000) return numberValue / 1000.0;
    return numberValue / 1000000.0;
}

function formatTime(value) {
    const totalSeconds = Math.floor(toSeconds(value));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = Math.floor(totalSeconds % 60);
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
}

function getPlayerLengthSeconds(player) {
    if (!player) return 0;
    let len = (player.length !== undefined ? Number(player.length) || 0 : 0);
    if (len <= 0 && player.metadata && player.metadata["mpris:length"])
        len = Number(player.metadata["mpris:length"]);
    return toSeconds(len);
}

function estimatePositionSec(basePosSec, baseTimestampMs, rate, totalLenSec, isPlaying) {
    if (!isPlaying) return Math.max(0, basePosSec);
    const elapsedSec = (Date.now() - baseTimestampMs) / 1000.0;
    const effectiveRate = (rate !== undefined && Number(rate) > 0) ? Number(rate) : 1.0;
    const estimated = basePosSec + (elapsedSec * effectiveRate);
    if (totalLenSec > 0)
        return Math.max(0, Math.min(totalLenSec, estimated));
    return Math.max(0, estimated);
}
