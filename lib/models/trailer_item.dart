import 'movie.dart';
import 'movie_info.dart';

/// One card of the home page's "Latest Trailers" row: the title, its best
/// YouTube trailer and a wide picture to show on the card.
class TrailerItem {
  final Movie movie;
  final Trailer trailer;
  final String backdrop; // wide image url
  final String published; // when the trailer went up (ISO text), for sorting
  const TrailerItem(this.movie, this.trailer, this.backdrop, this.published);
}
