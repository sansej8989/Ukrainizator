# modules/Sound.psm1
# ============================================================
# Ukrainizator - звуковий движок: синтез 16-біт WAV (chiptune),
# відтворення нот через звукову карту, fallback на [Console]::Beep.
# ============================================================

function New-ChiptuneWav {
    # Синтезує 16-біт моно WAV з послідовності нот. Band-limited square:
    # сума перших чотирьох непарних гармонік (1, 1/3, 1/5, 1/7) -
    # справжній "8-bit" тембр без зайвої жорсткості сирої square wave.
    param(
        [double[]]$Frequencies,   # Гц на кожну ноту, 0 = пауза
        [int[]]$Durations,        # мс на кожну ноту (той самий розмір масиву)
        [int]$SampleRate = 22050,
        [double]$Volume = 0.26
    )
    $bitsPerSample = 16
    $numChannels = 1
    $byteRate = $SampleRate * $numChannels * $bitsPerSample / 8
    $blockAlign = $numChannels * $bitsPerSample / 8

    $totalSamples = 0
    for ($n = 0; $n -lt $Durations.Count; $n++) { $totalSamples += [int]($SampleRate * $Durations[$n] / 1000.0) }
    $dataSize = $totalSamples * $blockAlign

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $ascii = [System.Text.Encoding]::ASCII

    $bw.Write($ascii.GetBytes('RIFF'))
    $bw.Write([int32](36 + $dataSize))
    $bw.Write($ascii.GetBytes('WAVE'))
    $bw.Write($ascii.GetBytes('fmt '))
    $bw.Write([int32]16)
    $bw.Write([int16]1)
    $bw.Write([int16]$numChannels)
    $bw.Write([int32]$SampleRate)
    $bw.Write([int32]$byteRate)
    $bw.Write([int16]$blockAlign)
    $bw.Write([int16]$bitsPerSample)
    $bw.Write($ascii.GetBytes('data'))
    $bw.Write([int32]$dataSize)

    for ($n = 0; $n -lt $Frequencies.Count; $n++) {
        $freq = $Frequencies[$n]
        $count = [int]($SampleRate * $Durations[$n] / 1000.0)
        $fadeLen = [Math]::Min(400, [int]($count / 3))
        for ($i = 0; $i -lt $count; $i++) {
            if ($freq -le 0) {
                $bw.Write([int16]0)
                continue
            }
            $t = $i / [double]$SampleRate
            $val = $Volume * 1.3 * (
                [Math]::Sin(2 * [Math]::PI * $freq * $t) +
                (1.0 / 3) * [Math]::Sin(2 * [Math]::PI * $freq * 3 * $t) +
                (1.0 / 5) * [Math]::Sin(2 * [Math]::PI * $freq * 5 * $t) +
                (1.0 / 7) * [Math]::Sin(2 * [Math]::PI * $freq * 7 * $t)
            )
            if ($fadeLen -gt 0) {
                if ($i -lt $fadeLen) { $val *= ($i / [double]$fadeLen) }
                elseif ($i -gt ($count - $fadeLen)) { $val *= (($count - $i) / [double]$fadeLen) }
            }
            $bw.Write([int16]([Math]::Round($val * 32767)))
        }
    }
    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose()
    $ms.Dispose()
    return $bytes
}

function Send-ChiptuneNotes {
    param([double[]]$Frequencies, [int[]]$Durations)
    $wavBytes = New-ChiptuneWav -Frequencies $Frequencies -Durations $Durations
    $playStream = New-Object System.IO.MemoryStream(,$wavBytes)
    $player = New-Object System.Media.SoundPlayer($playStream)
    $player.PlaySync()
    $playStream.Dispose()
}

function Invoke-Sound {
    # Єдина "звукова палітра" скрипта. Основний шлях - синтезований WAV через
    # звукову карту; якщо аудіопристрій недоступний (RDP без аудіо тощо) -
    # запасний варіант через [Console]::Beep() з тими самими нотами.
    param(
        [ValidateSet('Startup','StepSuccess','StepSkipped','StepError','Fanfare','CountdownTick','Cancel','Lock')]
        [string]$Type,
        [int]$Variant = 0
    )
    $freqs = @(); $durs = @()
    switch ($Type) {
        'Startup'      { $freqs = @(261, 329, 392, 523, 659);          $durs = @(55, 55, 55, 70, 140) }
        'StepSuccess'  { $b = 659 + ($Variant * 15); $freqs = @($b, $b * 1.5); $durs = @(60, 140) }
        'StepSkipped'  { $freqs = @(440);                                $durs = @(190) }
        'StepError'    { $freqs = @(220, 175, 147);                     $durs = @(140, 140, 240) }
        'Fanfare'      { $freqs = @(523, 659, 784, 1046, 784, 1046, 1318); $durs = @(110, 110, 110, 160, 110, 160, 380) }
        'CountdownTick'{ $p = if ($Variant % 2 -eq 0) { 880 } else { 660 }; $freqs = @($p); $durs = @(45) }
        'Cancel'       { $freqs = @(784, 587, 392);                     $durs = @(120, 120, 220) }
        'Lock'         { $freqs = @(440, 349, 440, 349);                $durs = @(110, 110, 110, 160) }
    }
    try {
        Send-ChiptuneNotes -Frequencies $freqs -Durations $durs
    } catch {
        try {
            for ($n = 0; $n -lt $freqs.Count; $n++) {
                if ($freqs[$n] -gt 0) { [Console]::Beep([int]$freqs[$n], $durs[$n]) }
            }
        } catch {}
    }
}
