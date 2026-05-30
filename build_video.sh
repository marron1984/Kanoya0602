#!/usr/bin/env bash
# 鹿のや 第1木曜「興味喚起（入口）」用リール動画ビルドスクリプト v2
# テーマ：初夏・世界観 / 鹿のいる風景 ～ 外でのカフェタイム
# 文字デザイン：明朝(Noto Serif CJK)＋下部スクリム＋細いルール＋字間広めの英字サブ
set -euo pipefail

JP="/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc"     # 和文：明朝ボールド
EN="/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"   # 欧文：サンセリフ
W=1080; H=1920; FPS=30
WORK="build_clips"
OUT="kanoya_shoka_reel.mp4"
TRANS=0.8
SCRIM="$WORK/scrim.png"
rm -rf "$WORK"; mkdir -p "$WORK"

# 下部スクリム（黒の縦グラデ・下ほど濃い）を生成
ffmpeg -y -f lavfi -i color=c=black:s=${W}x${H} -frames:v 1 \
  -vf "format=rgba,geq=r=0:g=0:b=0:a='clip((Y-1040)/880,0,1)*165'" "$SCRIM"

# 字間を広げるヘルパー（各文字の間に細いスペースを挿入）
space_out () { echo -n "$1" | sed 's/./& /g; s/ $//'; }

# シーケンス： ファイル|秒|和文|英字サブ|ズーム方向
clips=(
  "7C1A4295.jpg|4.2|初夏の、ひかり。|EARLY SUMMER LIGHT|in"
  "7C1A4305.jpg|3.8|風が、みどりを揺らす。|FRESH GREEN|out"
  "7C1A4285.jpg|4.2|鹿の、いる風景。|DEER IN VIEW|in"
  "S__63774765修.jpg|4.2|外の席で、ひと休み。|OUTDOOR SEATS|out"
  "S__63774766修.jpg|4.2|青空の下の、カフェ時間。|CAFE TIME|in"
  "7C1A4332.jpg|4.8|奈良春日　鹿のや|NARA KASUGA KANOYA|out"
)

make_clip () {
  local src="$1" dur="$2" jp="$3" en="$4" dir="$5" out="$6"
  local frames; frames=$(awk "BEGIN{printf \"%d\", $dur*$FPS}")
  local zexpr
  if [ "$dir" = "in" ]; then zexpr="min(zoom+0.0009,1.12)"
  else zexpr="if(eq(on,0),1.12,max(zoom-0.0009,1.0))"; fi

  local fin=0.7 fout=0.8
  local a="if(lt(t,${fin}),t/${fin},if(lt(t,${dur}-${fout}),1,max(0,(${dur}-t)/${fout})))"
  local ens; ens=$(space_out "$en")

  # 文字レイアウト（下部）: 細ルール → 和文(明朝) → 英字サブ
  local jpY="h-430" ruleY="h-480" enY="h-330"
  local textfilters="\
,drawbox=x=(w-150)/2:y=${ruleY}:w=150:h=2:color=white@0.85:t=fill:enable='gte(t,${fin})'\
,drawtext=fontfile='${JP}':text='${jp}':fontcolor=white:fontsize=70:x=(w-text_w)/2:y=${jpY}:\
shadowcolor=black@0.6:shadowx=0:shadowy=2:alpha='${a}'\
,drawtext=fontfile='${EN}':text='${ens}':fontcolor=white@0.92:fontsize=27:x=(w-text_w)/2:y=${enY}:\
shadowcolor=black@0.55:shadowx=0:shadowy=2:alpha='${a}'"

  ffmpeg -y -loop 1 -i "$src" -i "$SCRIM" -filter_complex "\
[0:v]split=2[bg][fg];\
[bg]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},\
gblur=sigma=34,eq=brightness=-0.05:saturation=1.05[bgb];\
[fg]scale=${W}:${H}:force_original_aspect_ratio=decrease[fgs];\
[bgb][fgs]overlay=(W-w)/2:(H-h)/2,format=yuv420p[comp];\
[comp]zoompan=z='${zexpr}':d=${frames}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':\
s=${W}x${H}:fps=${FPS}[zoomed];\
[zoomed][1:v]overlay=0:0${textfilters},\
trim=duration=${dur},setpts=PTS-STARTPTS,setsar=1[v]" \
    -map "[v]" -r $FPS -c:v libx264 -pix_fmt yuv420p -preset medium -crf 19 \
    -t "$dur" "$out"
}

i=0; segs=(); durs=()
for c in "${clips[@]}"; do
  IFS='|' read -r f d jp en dir <<< "$c"
  outc="$WORK/seg_$(printf '%02d' $i).mp4"
  echo ">> clip $i : $f (${d}s)"
  make_clip "$f" "$d" "$jp" "$en" "$dir" "$outc"
  segs+=("$outc"); durs+=("$d"); i=$((i+1))
done

inputs=(); for s in "${segs[@]}"; do inputs+=(-i "$s"); done
n=${#segs[@]}; filter=""; prev="[0:v]"; acc=${durs[0]}
for ((k=1;k<n;k++)); do
  off=$(awk "BEGIN{printf \"%.3f\", $acc-$TRANS}")
  if [ $k -eq $((n-1)) ]; then label="[vout]"; else label="[x$k]"; fi
  filter+="${prev}[${k}:v]xfade=transition=fade:duration=${TRANS}:offset=${off}${label};"
  prev="[x$k]"
  acc=$(awk "BEGIN{printf \"%.3f\", $acc+${durs[$k]}-$TRANS}")
done
filter="${filter%;}"

echo ">> total approx: ${acc}s"
ffmpeg -y "${inputs[@]}" -filter_complex "$filter" -map "[vout]" \
  -r $FPS -c:v libx264 -pix_fmt yuv420p -preset medium -crf 19 \
  -movflags +faststart "$OUT"
echo "DONE -> $OUT"
