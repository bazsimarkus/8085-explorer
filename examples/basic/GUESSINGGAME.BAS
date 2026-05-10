10 REM === GUESS THE NUMBER ===
20 PRINT "I'm thinking of a number"
30 PRINT "between 1 and 100..."
40 N=INT(RND(1)*100)+1
50 T=0
60 PRINT "Your guess";:INPUT G
70 T=T+1
80 IF G=N THEN PRINT "YES! Got it in";T;"tries!":GOTO 120
90 IF G<N THEN PRINT "Higher..."
100 IF G>N THEN PRINT "Lower..."
110 GOTO 60
120 PRINT "Play again? (Y/N)";:INPUT A$
130 IF A$="Y" OR A$="y" THEN 40