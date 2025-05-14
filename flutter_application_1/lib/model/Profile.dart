class Profile {
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String password;
  final String roomNumber;

  Profile({
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.roomNumber,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
        'roomNumber': roomNumber,
      };

  @override
  String toString() {
    return 'Profile(username: $username, name: $firstName $lastName, email: $email, room: $roomNumber)';
  }
}
