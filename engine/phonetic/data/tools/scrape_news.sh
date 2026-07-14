#!/usr/bin/env bash
# Harvest Bengali words from Bangladeshi newspaper sites (RSS feeds + front pages).
# Emits ONLY a word-frequency list (never article text) -> a wordlist, not a reproduction.
# Usage: ./scrape_news.sh [out_dir]   (default: current dir) -> news_words.tsv
set -u
OUT="${1:-.}"; mkdir -p "$OUT"
RAW="$OUT/news_raw.txt"; : > "$RAW"
UA="Mozilla/5.0 (compatible; BanglaDict/1.0)"

urls=(
  https://www.prothomalo.com/feed/ https://www.prothomalo.com/collection/latest/feed
  https://bangla.bdnews24.com/rss.xml https://bangla.bdnews24.com/
  https://www.jugantor.com/feed/rss.xml https://www.jugantor.com/
  https://www.kalerkantho.com/rss.xml https://www.kalerkantho.com/
  https://www.ittefaq.com.bd/rss.xml https://www.ittefaq.com.bd/
  https://samakal.com/feed https://samakal.com/
  https://www.banglatribune.com/feed/ https://www.banglatribune.com/
  https://www.jagonews24.com/rss/rss.xml https://www.jagonews24.com/
  https://www.banglanews24.com/rss/rss.xml https://www.banglanews24.com/
  https://www.risingbd.com/rss/rss.xml https://www.risingbd.com/
  https://www.dhakapost.com/rss/rss.xml https://www.dhakapost.com/
  https://www.dailynayadiganta.com/rss.xml https://www.dailynayadiganta.com/
  https://mzamin.com/rss.php https://mzamin.com/
  https://www.dainikamadershomoy.com/rss.xml https://www.dailyjanakantha.com/rss.xml
  https://www.somoynews.tv/rss.xml https://www.ajkerpatrika.com/feed
)

for u in "${urls[@]}"; do
  curl -sL --max-time 8 -A "$UA" "$u" 2>/dev/null \
    | perl -CSD -ne 'while(/([\x{0980}-\x{09FF}\x{200C}\x{200D}]{2,})/g){ print "$1\n" }' \
    >> "$RAW" 2>/dev/null
done

perl -CSD -MUnicode::Normalize -ne '
  chomp; $_=NFC($_); next unless /\p{Bengali}/;
  s/[\x{200C}\x{200D}]//g; next if length($_)<2;
  $c{$_}++;
  END{ for(sort{$c{$b}<=>$c{$a}} keys %c){ print "$_\t$c{$_}\n" } }
' "$RAW" > "$OUT/news_words.tsv"
rm -f "$RAW"
echo "DONE: $(wc -l < "$OUT/news_words.tsv" | tr -d ' ') distinct Bengali words -> $OUT/news_words.tsv"
