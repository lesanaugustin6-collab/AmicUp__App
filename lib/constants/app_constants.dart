const List<String> predefinedSportsOptions = [
  'Gym',
  'Running',
  'Hiking',
  'Cycling',
  'Yoga',
  'Basketball',
  'Swimming',
  'Football',
  'Tennis',
  'Climbing',
];

const List<String> predefinedHobbiesOptions = [
  'Coffee',
  'Reading',
  'Travel',
  'Cooking',
  'Movies',
  'Photography',
  'Gaming',
  'Art',
  'Brunch',
  'Music',
  'Volunteering',
  'Board Games',
];

const List<String> predefinedMusicOptions = [
  'Indie',
  'Pop',
  'Jazz',
  'R&B',
  'Rock',
  'Electronic',
  'Hip-Hop',
  'Classical',
  'Folk',
  'Latin',
];

const List<String> predefinedLifestyleOptions = [
  'Minimalist',
  'Wellness',
  'Night Owl',
  'Early Bird',
  'Dog Lover',
  'City Explorer',
  'Outdoorsy',
  'Homebody',
  'Fashion',
  'Foodie',
  'Bookish',
  'Adventure',
];

const List<String> worldCountryOptions = [
  'Afghanistan',
  'Albania',
  'Algeria',
  'Argentina',
  'Australia',
  'Austria',
  'Belgium',
  'Brazil',
  'Canada',
  'Chile',
  'China',
  'Colombia',
  'Croatia',
  'Czech Republic',
  'Denmark',
  'Egypt',
  'Finland',
  'France',
  'Germany',
  'Greece',
  'Hungary',
  'India',
  'Indonesia',
  'Ireland',
  'Italy',
  'Japan',
  'Kenya',
  'Malaysia',
  'Mexico',
  'Moldova',
  'Netherlands',
  'New Zealand',
  'Nigeria',
  'Norway',
  'Poland',
  'Portugal',
  'Romania',
  'Saudi Arabia',
  'Serbia',
  'Singapore',
  'Slovakia',
  'South Africa',
  'South Korea',
  'Spain',
  'Sweden',
  'Switzerland',
  'Thailand',
  'Turkey',
  'Ukraine',
  'United Arab Emirates',
  'United Kingdom',
  'United States',
  'Vietnam',
];

const List<String> languageOptions = [
  'English',
  'Spanish',
  'French',
  'German',
  'Mandarin',
  'Arabic',
  'Hindi',
  'Portuguese',
  'Russian',
  'Japanese',
  'Korean',
  'Italian',
  'Dutch',
  'Polish',
  'Turkish',
  'Romanian',
  'Ukrainian',
  'Vietnamese',
  'Thai',
  'Indonesian',
  'Greek',
  'Hebrew',
  'Swedish',
  'Czech',
  'Hungarian',
  'Danish',
  'Finnish',
  'Norwegian',
  'Tagalog',
  'Malay',
];

const List<String> lockedPromptQuestionOptions = [
  "I'm looking for a friend who...",
  "My ideal way to spend a free afternoon with friends is...",
  "The fastest way to become my friend is...",
];

const List<String> defaultInterestChoices = <String>[
  ...predefinedSportsOptions,
  ...predefinedHobbiesOptions,
  ...predefinedMusicOptions,
  ...predefinedLifestyleOptions,
];

class AppConstants {
  static const List<String> predefinedSports = predefinedSportsOptions;
  static const List<String> predefinedHobbies = predefinedHobbiesOptions;
  static const List<String> predefinedMusic = predefinedMusicOptions;
  static const List<String> predefinedLifestyle = predefinedLifestyleOptions;
  static const List<String> worldCountries = worldCountryOptions;
  static const List<String> languages = languageOptions;
  static const List<String> lockedPromptQuestions = lockedPromptQuestionOptions;
  // ignore: constant_identifier_names
  static const List<String> LOCKED_ICEBREAKER_QUESTIONS =
      lockedPromptQuestionOptions;
  static const List<String> defaultInterestOptions = <String>[
    ...predefinedSportsOptions,
    ...predefinedHobbiesOptions,
    ...predefinedMusicOptions,
    ...predefinedLifestyleOptions,
  ];

  static const Map<String, List<String>> predefinedInterestMap = {
    'sports': predefinedSportsOptions,
    'hobbies': predefinedHobbiesOptions,
    'music': predefinedMusicOptions,
    'lifestyle': predefinedLifestyleOptions,
  };
}
