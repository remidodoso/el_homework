NOTES

To run this you will need to install a few modules, one of which has an annoying nunber
of dependencies (Geo::Calc), along with DBI::SQLite and the others referred to. The 
sample output is perfectly real, though.

I sanity checked the output vs Google Maps and am confident it's sane, within what seem
to be fairly relaxed data quality standards at the origin.

I wasn't able to get SSLeay headers and the like installed properly but the http: URL
worked fine. I'm on WSL 2 for this, and I didn't feel like sorting that out.

You probably realize that the data is weird in at least one fundamental way, that the
number of permits for a vendor is an upper bound on locations, not the number of
locations. I think the vendor with the most permitted locations has 27, and as far as
I can tell does business only in one. So, if the goal is to implement "where can I get a
hot dog, on the first try" this would not be my recommendation.

The "schedules" URLs point to what seems to be a currently nonfunctional DB visualization 
of some kind so I wasn't able to glean anything there.

I thought about what to do with this for a long time and was thinking it might be fun 
to turn it into some sort of game, was thinking a very simple 4X-like thing where the 
permitted locations are cities/star systems/??? and the resources they have are determined 
somehow by the data. But the data is just too ad hoc for that to make enough sense. I was 
so hoping that some planets could have hot dogs, some could have falafel, etc, but of 
course that's not in this permitting database nor would it make sense for it to be.

I was always going to start by loading data into SQLite, so that's what it wound up being.
I did want to use distances from one location to another in some way, or some kind of 
geo querying. I'm not sure what 2d query features SQLite supports so I went with my 
brute force table of distances.

I hope you found it interesting, or appropriate, or positively revealing, or something.

Regards,

  -j 