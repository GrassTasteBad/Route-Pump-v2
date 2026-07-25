<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    public function register(Request $request)
    {
        $fields = $request->validate([
            'name' => 'required|string',
            'email' => 'required|string|unique:users,email',
            'password' => 'required|string|confirmed',
            'role' => 'required|string|in:motorist,partner,admin',
            'station_id' => 'nullable|string',
        ]);

        $user = User::create([
            'id' => (string) Str::uuid(),
            'name' => $fields['name'],
            'email' => $fields['email'],
            'password' => bcrypt($fields['password']),
            'role' => $fields['role'],
            'station_id' => $fields['station_id'] ?? null,
        ]);

        $token = $user->createToken('routepump_token')->plainTextToken;

        return response([
            'user' => $user->load('vehicle', 'station'),
            'token' => $token,
        ], 210); // Custom success code or 201
    }

    public function login(Request $request)
    {
        $fields = $request->validate([
            'email' => 'required|string',
            'password' => 'required|string',
        ]);

        $user = User::where('email', $fields['email'])->first();

        if (!$user || !Hash::check($fields['password'], $user->password)) {
            return response([
                'message' => 'Bad credentials',
            ], 401);
        }

        if ($user->status === 'deactivated') {
            return response([
                'message' => 'Your account has been deactivated.',
            ], 403);
        }

        $token = $user->createToken('routepump_token')->plainTextToken;

        return response([
            'user' => $user->load('vehicle', 'station'),
            'token' => $token,
        ], 200);
    }

    public function logout(Request $request)
    {
        $request->user()->tokens()->delete();

        return response([
            'message' => 'Logged out',
        ], 200);
    }

    public function me(Request $request)
    {
        return response($request->user()->load('vehicle', 'station'), 200);
    }
}
