local config = {}

-- Difficulty is based on how "obvious" the word is for that theme, not length.
-- Easy = first thing you think of. Medium = you know it but need a second.
-- Hard = genuinely obscure or very specific.
-- No hyphens on words players would never type with one (Spiderman not Spider-Man etc.)

config.themes = {

	-- ── ANIMALS ──────────────────────────────────────────────────────────────
	{
		name = "Animals",
		easy = {
			"elephant","lion","tiger","shark","penguin","dolphin","bear",
			"giraffe","monkey","snake","eagle","frog","rabbit","wolf","dog",
			"cat","horse","cow","pig","chicken","duck","fish","deer","fox","bee",
			"parrot","turtle","crocodile","zebra","panda",
		},
		medium = {
			"gorilla","cheetah","kangaroo","flamingo","octopus","peacock",
			"koala","toucan","butterfly","jellyfish","hamster","seahorse",
			"owl","lobster","seal","bat","camel","rhino","hippo","walrus",
			"python","cobra","meerkat","raccoon","skunk","hedgehog",
			"armadillo","narwhal","chameleon","platypus","capybara",
		},
		hard = {
			"iguana","chimpanzee","pelican","scorpion","piranha","axolotl",
			"fossa","numbat","wolverine","salamander","vulture","jaguar",
			"tapir","manatee","okapi","binturong","pangolin","quokka",
			"cassowary","kinkajou",
		},
	},

	-- ── SAVORY FOOD ──────────────────────────────────────────────────────────
	{
		name = "Savory Food",
		easy = {
			"pizza","burger","hot dog","tacos","sandwich","spaghetti",
			"fried chicken","grilled cheese","soup","steak","pasta",
			"bacon","fries","nachos","sushi","rice","bread","noodles",
			"omelette","mac and cheese","meatballs","salad","wings","wrap","kebab",
		},
		medium = {
			"burrito","lasagna","dumplings","quesadilla","fajita",
			"hummus","paella","risotto","pho","pad thai","gyros",
			"enchiladas","ramen","curry","schnitzel","pierogi","goulash",
			"shakshuka","bibimbap","poutine","biryani","empanada",
			"spring roll","banh mi","ceviche","jerk chicken","bratwurst",
		},
		hard = {
			"calzone","cassoulet","bouillabaisse","ratatouille",
			"chimichanga","birria","moussaka","kedgeree","rendang",
			"bobotie","churrasco","saltimbocca","borscht","mole",
			"tagine","peri peri","wiener schnitzel","cotoletta",
		},
	},

	-- ── SWEET TREATS ─────────────────────────────────────────────────────────
	{
		name = "Sweet Treats",
		easy = {
			"ice cream","cake","cookies","chocolate","candy","cupcake",
			"donut","brownie","lollipop","cotton candy","pie","gummy bears",
			"marshmallow","cheesecake","pudding","muffin","waffle",
			"pancake","milkshake","toffee","fudge","caramel","sundae","popsicle",
		},
		medium = {
			"churros","crepes","macarons","cannoli","trifle","mousse",
			"mochi",
			"custard","fruit tart","creme brulee","madeleine","pavlova",
			"baklava","halva","profiterole",
		},
		hard = {
			"knafeh","brigadeiro","alfajores","kouign amann","financier",
			"rum baba","paris brest","opera cake","millefeuille",
			"dobos torte","basbousa","schwarzwalder kirschtorte",
			"religieuse","saint honore","tarte tatin",
		},
	},

	-- ── SNACKS & STREET FOOD ─────────────────────────────────────────────────
	{
		name = "Snacks & Street Food",
		easy = {
			"popcorn","chips","pretzel","corn dog","hot dog","cotton candy",
			"funnel cake","nachos","french fries","pizza slice","onion rings",
			"soft pretzel","churros","popsicle","candy floss",
		},
		medium = {
			"empanada","falafel","spring roll","samosa","takoyaki",
			"arepas","elote","bao bun","tteokbokki","gozleme",
			"dirty fries","okonomiyaki","pani puri","choripan","jibarito",
		},
		hard = {
			"currywurst","tequeños","bitterballen","vada pav","kachori",
			"bunny chow","roti canai","sabich","coxinha","pupusa",
			"pandebono","doubles","boerewors","cachapa","chili dog",
		},
	},

	-- ── BREAKFAST ────────────────────────────────────────────────────────────
	{
		name = "Breakfast",
		easy = {
			"pancakes","waffles","eggs","bacon","toast","cereal",
			"orange juice","oatmeal","bagel","croissant","sausage",
			"butter","jam","coffee","milk",
		},
		medium = {
			"french toast","hash browns","crepes","granola","yogurt",
			"scrambled eggs","english muffin","avocado toast","omelette","biscuits and gravy",
			"porridge","smoothie","eggs benedict","frittata","breakfast burrito",
		},
		hard = {
			"shakshuka","huevos rancheros","congee","full english",
			"chilaquiles","croque madame","strata","kedgeree",
			"acai bowl","manakeesh","tamagoyaki","ful medames",
			"johnnycakes","revuelto","rosti",
		},
	},

	-- ── COUNTRIES ────────────────────────────────────────────────────────────
	{
		name = "Countries",
		easy = {
			"USA","France","Japan","Brazil","China","Australia",
			"Italy","Canada","Mexico","Germany","Spain","Russia",
			"India","Egypt","England","Scotland","Ireland","Greece",
			"Turkey","Sweden","Portugal","Argentina","Norway","Denmark","South Korea",
		},
		medium = {
			"Thailand","Vietnam","Colombia","Finland","Peru",
			"Morocco","Kenya","Malaysia","Philippines","Indonesia",
			"Ukraine","Chile","Lebanon","Nepal","Ethiopia",
			"Venezuela","Nigeria","Pakistan","Israel","New Zealand",
			"Belgium","Switzerland","Hungary","Romania","Czech Republic",
		},
		hard = {
			"Bhutan","Kyrgyzstan","Suriname","Djibouti","Liechtenstein",
			"Vanuatu","Andorra","San Marino","Kiribati","Nauru",
			"Palau","Tuvalu","Comoros","Eritrea","Eswatini",
			"Timor Leste","Equatorial Guinea","Mauritania","Burkina Faso","Tajikistan",
		},
	},

	-- ── SPORTS ───────────────────────────────────────────────────────────────
	{
		name = "Sports",
		easy = {
			"soccer","basketball","tennis","swimming","baseball",
			"football","golf","boxing","gymnastics","volleyball",
			"hockey","cycling","skiing","surfing","wrestling",
			"running","fishing","climbing","rowing",
		},
		medium = {
			"badminton","rugby","cricket","archery","kayaking",
			"snowboarding","skateboarding","lacrosse","water polo",
			"fencing","diving","table tennis","handball","track and field",
			"triathlon","pentathlon","judo","karate","taekwondo",
		},
		hard = {
			"squash","polo","bobsled","curling","luge",
			"sepak takraw","kabaddi","hurling","korfball","pelota",
			"skeleton","biathlon","orienteering","canoe polo","underwater hockey",
			"real tennis","jai alai","buzkashi","bossaball","tchoukball",
		},
	},

	-- ── HOUSEHOLD ITEMS ──────────────────────────────────────────────────────
	{
		name = "Household Items",
		easy = {
			"refrigerator","television","couch","lamp","toilet",
			"sink","microwave","vacuum","clock","mirror","table",
			"chair","door","window","bed","shelf","drawer","carpet","curtain","pillow",
		},
		medium = {
			"blender","toaster","bookshelf","umbrella","scissors",
			"blanket","spatula","kettle","broom","mop","candle",
			"picture frame","fan","washing machine","dishwasher",
			"bath mat","light switch","power strip","coat rack","laundry basket",
		},
		hard = {
			"dustpan","plunger","garden hose","lawnmower","smoke alarm",
			"doormat","dish rack","shower curtain","ironing board","dehumidifier",
			"drawer organizer","drain stopper","caulking gun","pipe wrench",
			"stud finder","putty knife",
		},
	},

	-- ── OCCUPATIONS ──────────────────────────────────────────────────────────
	{
		name = "Occupations/Jobs",
		easy = {
			"doctor","teacher","firefighter","police officer","chef",
			"pilot","nurse","farmer","actor","dentist",
			"lawyer","baker","artist","soldier","bus driver",
			"plumber","mechanic","cashier","waiter","librarian",
		},
		medium = {
			"surgeon","astronaut","veterinarian","architect",
			"scientist","detective","journalist","photographer","zookeeper",
			"animator","paramedic","judge","carpenter","electrician",
			"pharmacist","psychologist","social worker","accountant","marine biologist","optician",
		},
		hard = {
			"sommelier","actuary","taxidermist","cartographer","oncologist",
			"stenographer","glazier","coroner","orthodontist","entomologist",
			"cryptographer","archivist","metallurgist","radiologist",
			"epidemiologist","hydrologist","toxicologist","pathologist","podiatrist",
		},
	},


	
	-- ── SPACE ────────────────────────────────────────────────────────────────
	{
		name = "Space",
		easy = {
			"moon","sun","star","planet","rocket",
			"astronaut","black hole","asteroid","galaxy","comet",
			"satellite","Earth","Mars","meteor","telescope",
			"Jupiter","Saturn","Venus","Mercury","orbit",
		},
		medium = {
			"nebula","supernova","constellation","spacewalk",
			"space station","solar flare","lunar eclipse","solar eclipse",
			"wormhole","shooting star","big bang","atmosphere",
			"solar system","Milky Way","neutron star","red dwarf",
			"space shuttle","launch pad","gravity","light year",
		},
		hard = {
			"pulsar","quasar","dark matter","parsec","magnetar",
			"accretion disk","Lagrange point","red giant",
			"cosmic ray","Dyson sphere","Kuiper Belt","Oort Cloud",
			"gravitational lensing","event horizon","Chandrasekhar limit",
		},
	},

	-- ── VEHICLES ─────────────────────────────────────────────────────────────
	{
		name = "Vehicles",
		easy = {
			"car","bus","airplane","bicycle","motorcycle",
			"boat","train","helicopter","truck","submarine",
			"tractor","ambulance","fire truck","taxi","ship",
			"van","scooter","canoe","jet","skateboard",
		},
		medium = {
			"hovercraft","snowmobile","zeppelin","hot air balloon",
			"ferry","tram","forklift","bulldozer","jet ski",
			"cable car","go kart","blimp","glider","kayak",
			"monster truck","golf cart","food truck","speedboat","rickshaw",
		},
		hard = {
			"dune buggy","tugboat","aircraft carrier","excavator","crane",
			"unicycle","gondola","hydrofoil","maglev train",
			"airboat","paddleboat","bathyscaphe","gyrocopter",
			"ekranoplan","snowcat","velocipede",
		},
	},

	-- ── EMOTIONS ─────────────────────────────────────────────────────────────
	{
		name = "Emotions",
		easy = {
			"happy","sad","angry","scared","excited",
			"surprised","nervous","tired","bored","proud",
			"confused","lonely","silly","love","worried",
			"calm","joyful","shy","grateful","embarrassed",
		},
		medium = {
			"jealous","frustrated","disgusted","amazed","curious",
			"relaxed","grumpy","confident","hyper","cheerful",
			"overwhelmed","hopeful","miserable","energetic","peaceful",
			"sentimental","nostalgic","anxious","devastated","ecstatic",
		},
		hard = {
			"melancholy","apprehensive","exhilarated","remorseful",
			"euphoric","despondent","wistful","indifferent",
			"ambivalent","forlorn","schadenfreude","disillusionment",
			"trepidation","ennui","magnanimous","vindicated",
		},
	},

	

	-- ── SUPERHEROES ──────────────────────────────────────────────────────────
	{
		name = "Superheroes",
		easy = {
			"Spiderman","Batman","Superman","Iron Man","Captain America",
			"Hulk","Thor","Wonder Woman","Flash","Wolverine",
			"Aquaman","Black Panther","Deadpool","Venom","Thanos",
		},
		medium = {
			"Black Widow","Doctor Strange","Ant Man","Scarlet Witch",
			"Daredevil","Green Lantern","Cyclops","Storm",
			"Green Arrow","Shazam","Iceman","Beast","Nightcrawler",
			"Silver Surfer","Hawkeye","Gambit","Rogue","Mystique",
		},
		hard = {
			"Moon Knight","Ms Marvel","Miles Morales","She Hulk",
			"War Machine","Star Lord","Gamora","Falcon",
			"Nova","Blue Marvel","America Chavez","Namorita",
			"Quasar","Darkhawk","Night Thrasher","Justice","Rage",
		},
	},

	-- ── FRUITS ───────────────────────────────────────────────────────────────
	{
		name = "Fruits",
		easy = {
			"apple","banana","orange","strawberry","watermelon",
			"grapes","mango","pineapple","cherry","lemon",
			"peach","blueberry","coconut","kiwi","pear",
			"lime","melon",
		},
		medium = {
			"apricot","pomegranate","avocado","papaya","dragon fruit",
			"guava","persimmon","lychee","passion fruit","cantaloupe",
			"grapefruit","nectarine","cranberry","tangerine","blackberry",
			"gooseberry","boysenberry","quince","date","elderberry",
		},
		hard = {
			"durian","rambutan","mangosteen","cherimoya","jackfruit",
			"carambola","feijoa","longan","soursop","ackee",
			"salak","tamarind","sapodilla","jabuticaba","langsat",
			"santol","mamey sapote","pitanga","noni","cupuacu",
		},
	},

	-- ── VEGETABLES ───────────────────────────────────────────────────────────
	{
		name = "Vegetables",
		easy = {
			"carrot","broccoli","tomato","potato",
			"onion","cucumber","spinach","pepper","mushroom",
			"peas","lettuce","garlic","cabbage",
			"pumpkin"
		},
		medium = {
			"cauliflower","eggplant","sweet potato","brussels sprouts",
			"artichoke","beet","turnip","squash","radish","kale",
			"bok choy","okra","parsnip","swiss chard","endive",
			"watercress","rocket","shallot","fennel","butternut squash",
		},
		hard = {
			"kohlrabi","celeriac","jicama","romanesco","salsify",
			"rutabaga","taro","daikon","fiddlehead","chayote",
			"cassava","lotus root","nopales","samphire",
			"purslane","mizuna","cardoon","scorzonera","agretti",
		},
	},



	-- ── CLOTHING ─────────────────────────────────────────────────────────────
	{
		name = "Clothing",
		easy = {
			"t shirt","jeans","jacket","dress","shoes",
			"hat","socks","boots","hoodie","scarf",
			"gloves","shorts","sneakers",
			"coat","skirt","tie","suit"
		},
		medium = {
			"trench coat","overalls","blazer","kimono","poncho",
			"turtleneck","leggings","windbreaker","beanie","tank top",
			"tracksuit","raincoat","tuxedo","sandals","flip flops",
			"mittens","beret","crop top","dungarees","kilt",
			"corset","onesie","sundress","top hat","wedding dress",
		},
		hard = {
			"lederhosen","sari","kaftan","dirndl","cheongsam",
			"abaya","dashiki","yukata","doublet","culottes",
			"tabard","dhoti","sarong","muumuu","balaclava",
			"boilersuit","tutu","burqa","haori","peplos",
		},
	},

	-- ── COLORS ───────────────────────────────────────────────────────────────
	{
		name = "Colors",
		easy = {
			"red","blue","green","yellow","orange",
			"pink","purple","black","white","brown",
			"grey","gold","silver","rainbow"
		},
		medium = {
			"crimson","scarlet","magenta","amber","olive",
			"hot pink","forest green","lavender","electric blue","lime green",
			"sky blue","cobalt","rust","mustard","rose gold",
			"indigo","peach","lilac","turquoise","maroon",
			"navy","burgundy","charcoal","beige","mint green",
		},
		hard = {
			"vermilion","cerulean","chartreuse","ochre","viridian",
			"sienna","ecru","taupe","puce","sanguine",
			"umber","carmine","sepia","gamboge","onyx",
			"wenge","bronze","copper","smalt","cinnabar",
		},
	},

	-- ── BOARD GAMES ──────────────────────────────────────────────────────────
	{
		name = "Board Games",
		easy = {
			"chess","checkers","Monopoly","Uno","Scrabble",
			"Jenga","Connect Four","Battleship",
			"Snakes and Ladders","Ludo","Noughts and Crosses","Rock Paper Scissors",
		},
		medium = {
			"dominoes","backgammon","mahjong","Catan","Risk",
			"Ticket to Ride","Trivial Pursuit","Yahtzee","Boggle",
			"Cranium","Taboo","Guess Who","Reversi","Othello","Operation",
		},
		hard = {
			"Agricola","Pandemic","Azul","Wingspan","Codenames",
			"Splendor","Viticulture","Gloomhaven","Power Grid",
			"Twilight Imperium","Terraforming Mars","7 Wonders",
			"Brass Birmingham","Through the Ages","Spirit Island",
		},
	},

	-- ── VIDEO GAMES ──────────────────────────────────────────────────────────
	{
		name = "Video Games",
		easy = {
			"Minecraft","Mario","Fortnite","Pokemon","Roblox",
			"Among Us","Pac Man","Call of Duty","FIFA",
			"GTA","Zelda","Sonic","Angry Birds",
		},
		medium = {
			"Skyrim","Overwatch","League of Legends","Valorant",
			"Elden Ring","Animal Crossing","Red Dead Redemption",
			"Apex Legends","Stardew Valley","The Sims","Resident Evil",
			"Dark Souls","Cyberpunk","Fallout","God of War",
		},
		hard = {
			"Hollow Knight","Celeste","Undertale","Disco Elysium",
			"Outer Wilds","Subnautica","Noita","Dwarf Fortress",
			"Return of the Obra Dinn","Kenshi","Pathologic",
			"Morrowind","Nethack","Caves of Qud","Rain World",
		},
	},

	-- ── MUSICAL INSTRUMENTS ──────────────────────────────────────────────────
	{
		name = "Musical Instruments",
		easy = {
			"guitar","piano","drums","violin","trumpet",
			"flute","saxophone","bass","ukulele","microphone",
			"electric guitar","xylophone",
		},
		medium = {
			"oboe","bassoon","mandolin","banjo","accordion",
			"harmonica","sitar","bagpipes","french horn",
			"tuba","snare drum","cymbals","tambourine","didgeridoo",
			"marimba","vibraphone","triangle","cowbell","lute",
		},
		hard = {
			"theremin","hurdy gurdy","dulcimer","theorbo","ocarina",
			"flugelhorn","sousaphone","mellophone","cimbalom",
			"hardanger fiddle","shamisen","erhu","bouzouki","koto",
			"sarod","rebab","kanun","guqin","fujara",
		},
	},




	-- ── TV SHOWS ─────────────────────────────────────────────────────────────
	{
		name = "TV Shows",
		easy = {
			"Friends","The Simpsons","Spongebob","Game of Thrones","Breaking Bad",
			"Stranger Things","The Office","Peppa Pig","Scooby Doo",
			"South Park","Family Guy","Naruto","Dragon Ball","Pokemon",
		},
		medium = {
			"The Wire","Succession","The Sopranos","Lost","Dexter",
			"Westworld","Peaky Blinders","Better Call Saul","Black Mirror","The Crown",
			"Squid Game","Ted Lasso","Euphoria","The Boys","Its Always Sunny",
		},
		hard = {
			"The Leftovers","Deadwood","The Terror","Mindhunter",
			"The Knick","Rectify","Carnivale","The Expanse","Severance",
			"Mr Robot","Station Eleven","Halt and Catch Fire","Rubicon",
			"Treme","Enlightened",
		},
	},


	-- ── FAMOUS PEOPLE ────────────────────────────────────────────────────────
	{
		name = "Famous People",
		easy = {
			"Albert Einstein","Michael Jordan","Michael Jackson","Elon Musk","Beyonce",
			"Taylor Swift","Leonardo da Vinci","Isaac Newton","Barack Obama","Queen Elizabeth",
			"Abraham Lincoln","Napoleon","Cleopatra","Shakespeare","Steve Jobs",
		},
		medium = {
			"Nikola Tesla","Marie Curie","Galileo","Darwin","Mozart",
			"Beethoven","Pablo Picasso","Salvador Dali","Frida Kahlo","Nelson Mandela",
			"Mahatma Gandhi","Aristotle","Plato","Socrates","Julius Caesar",
		},
		hard = {
			"Diogenes","Hypatia","Avicenna","Hildegard of Bingen",
			"Srinivasa Ramanujan","Ada Lovelace","Ignaz Semmelweis","Gottfried Leibniz",
			"Gregor Mendel","Rosalind Franklin","Emmy Noether","Alan Turing",
			"Tycho Brahe","Al Khwarizmi","Giordano Bruno",
		},
	},

}

return config