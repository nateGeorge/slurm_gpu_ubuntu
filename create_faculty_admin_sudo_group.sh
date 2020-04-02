# this is for creating a group for admins/faculty that have sudo priveleges
# note: this still doesn't quite work
# create sudo rule
# https://serverfault.com/a/560237/305991

ipa sudorule-add --cmdcat=all --hostcat=all --runasuser=all All

# create faculty group
ipa group-add faculty

ipa sudorule-add-group --groups=faculty All
