#!/usr/bin/env bash
# 鹿のや 第1木曜「興味喚起（入口）」用リール動画ビルドスクリプト
# テーマ：初夏・世界観 / 鹿のいる風景 ～ 外でのカフェタイム
# 出力：縦型 1080x1920 / 30fps / クロスフェード + ゆっくりズーム
set -euo pipefail

FONT="/usr/share/fonts/truetype/fonts-japanese-gothic.ttf"
W=1080; H=1920; FPS=30
WORK="build_clips"
OUT="kanoya_shoka_reel.mp4"
TRANS=0.8   # クロスフェード秒数
rm -rf "$WORK"; mkdir -p "$WORK"

# シーケンス定義： ファイル|表示秒|オーバーレイ文字(空可)|ズーム方向(in/out)
clips=(
  "7C1A4295.jpg|4.2|初夏の、ひかり。|in"
  "7C1A4305.jpg|3.8||out"
  "7C1A4285.jpg|4.2|鹿の、いる風景。|in"
  "S__63774765修.jpg|4.2|外の席で、ひと休み。|out"
  "S__63774766修.jpg|4.2|青空の下の、カフェ時間。|in"
  "7C1A4332.jpg|4.8|奈良春日 鹿のや|out"
)

make_clip () {
  local src="$1" dur="$2" text="$3" dir="$4" out="$5"
  local frames; frames=$(awk "BEGIN{printf \"%d\", $dur*$FPS}")
  # ズーム式（ゆっくり / 方向で開始倍率を変える）
  local zexpr
  if [ "$dir" = "in" ]; then
    zexpr="min(zoom+0.0009,1.12)"
  else
    zexpr="if(eq(on,0),1.12,max(zoom-0.0009,1.0))"
  fi
  # テキストオーバーレイ（フェードイン/アウト付き）
  local textfilter=""
  if [ -n "$text" ]; then
    local fin=0.6 fout=0.8
    local alpha="if(lt(t,${fin}),t/${fin},if(lt(t,${dur}-${fout}),1,max(0,(${dur}-t)/${fout})))"
    textfilter=",drawtext=fontfile='${FONT}':text='${text}':fontcolor=white:fontsize=66:\
x=(w-text_w)/2:y=h-360:shadowcolor=black@0.55:shadowx=0:shadowy=3:\
alpha='${alpha}':line_spacing=14"
  fi
  ffmpeg -y -loop 1 -i "$src" -filter_complex "\
[0:v]split=2[bg][fg];\
[bg]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},\
gblur=sigma=34,eq=brightness=-0.05:saturation=1.05[bgb];\
[fg]scale=${W}:${H}:force_original_aspect_ratio=decrease[fgs];\
[bgb][fgs]overlay=(W-w)/2:(H-h)/2,format=yuv420p[comp];\
[comp]zoompan=z='${zexpr}':d=${frames}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':\
s=${W}x${H}:fps=${FPS}${textfilter},\
trim=duration=${dur},setpts=PTS-STARTPTS,setsar=1[v]" \
    -map "[v]" -r $FPS -c:v libx264 -pix_fmt yuv420p -preset medium -crf 19 \
    -t "$dur" "$out"
}

i=0
segs=()
durs=()
for c in "${clips[@]}"; do
  IFS='|' read -r f d t dir <<< "$c"
  outc="$WORK/seg_$(printf '%02d' $i).mp4"
  echo ">> clip $i : $f (${d}s)"
  make_clip "$f" "$d" "$t" "$dir" "$outc"
  segs+=("$outc")
  durs+=("$d")
  i=$((i+1))
done

# xfade チェーンを組み立て
inputs=()
for s in "${segs[@]}"; do inputs+=(-i "$s"); done

n=${#segs[@]}
filter=""
prev="[0:v]"
acc=${durs[0]}
for ((k=1;k<n;k++)); do
  off=$(awk "BEGIN{printf \"%.3f\", $acc-$TRANS}")
  if [ $k -eq $((n-1)) ]; then label="[vout]"; else label="[x$k]"; fi
  filter+="${prev}[${k}:v]xfade=transition=fade:duration=${TRANS}:offset=${off}${label};"
  prev="[x$k]"
  acc=$(awk "BEGIN{printf \"%.3f\", $acc+${durs[$k]}-$TRANS}")
done
filter="${filter%;}"

echo ">> total duration approx: ${acc}s"
ffmpeg -y "${inputs[@]}" -filter_complex "$filter" -map "[vout]" \
  -r $FPS -c:v libx264 -pix_fmt yuv420p -preset medium -crf 19 \
  -movflags +faststart "$OUT"

echo "DONE -> $OUT"
ffprobe -v error -show_entries format=duration:stream=width,height -of default=nw=1 "$OUT"
