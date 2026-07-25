<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class UserController extends Controller
{
    // GET /api/users
    // Returns all users, optionally filtered by ?role=partner|motorist|admin
    public function index(Request $request)
    {
        $query = User::with('station')->orderBy('created_at', 'desc');

        if ($request->has('role') && in_array($request->role, ['motorist', 'partner', 'admin'])) {
            $query->where('role', $request->role);
        }

        $users = $query->get()->map(function ($user) {
            return [
                'id'         => $user->id,
                'name'       => $user->name,
                'email'      => $user->email,
                'role'       => $user->role,
                'status'     => $user->status,
                'station_id' => $user->station_id,
                'station'    => $user->station ? [
                    'id'     => $user->station->id,
                    'name'   => $user->station->name,
                    'branch' => $user->station->branch,
                ] : null,
                'created_at' => $user->created_at,
            ];
        });

        return response($users, 200);
    }

    // POST /api/users
    // Creates a new user account
    public function store(Request $request)
    {
        $fields = $request->validate([
            'name'       => 'required|string|max:255',
            'email'      => 'required|email|unique:users,email',
            'password'   => 'required|string|min:6',
            'role'       => 'required|string|in:motorist,partner,admin',
            'station_id' => 'nullable|string|exists:gas_stations,id',
        ]);

        // station_id is only meaningful for partner role
        $stationId = ($fields['role'] === 'partner') ? ($fields['station_id'] ?? null) : null;

        $user = User::create([
            'id'         => (string) Str::uuid(),
            'name'       => $fields['name'],
            'email'      => $fields['email'],
            'password'   => bcrypt($fields['password']),
            'role'       => $fields['role'],
            'station_id' => $stationId,
        ]);

        return response([
            'message' => 'User account created successfully.',
            'user'    => $user->load('station'),
        ], 201);
    }

    // DELETE /api/users/{id}
    // Deactivates a user; cannot deactivate yourself
    public function destroy(Request $request, $id)
    {
        if ($request->user()->id === $id) {
            return response(['message' => 'You cannot deactivate your own account.'], 403);
        }

        $user = User::find($id);

        if (!$user) {
            return response(['message' => 'User not found.'], 404);
        }

        $user->status = 'deactivated';
        $user->save();

        return response(['message' => 'User account deactivated successfully.'], 200);
    }

    // GET /api/leaderboard
    // Returns top motorists ranked by trust score and price report count
    public function leaderboard(Request $request)
    {
        $currentUser = $request->user();

        $motorists = User::where('role', 'motorist')
            ->where('status', 'active')
            ->withCount('reportedPrices')
            ->orderBy('trust_score', 'desc')
            ->orderBy('reported_prices_count', 'desc')
            ->get();

        $rankedList = [];
        $myRankData = null;

        foreach ($motorists as $index => $u) {
            $rank = $index + 1;
            $score = (int)($u->trust_score ?? 50);

            $tier = 'Bronze Reporter';
            if ($score >= 90) $tier = 'Platinum Reporter';
            elseif ($score >= 80) $tier = 'Gold Reporter';
            elseif ($score >= 65) $tier = 'Silver Reporter';

            $item = [
                'rank'            => $rank,
                'id'              => $u->id,
                'name'            => $u->name,
                'email'           => $u->email,
                'trust_score'     => $score,
                'tier'            => $tier,
                'reports_count'   => $u->reported_prices_count ?? 0,
                'is_current_user' => $currentUser && $currentUser->id === $u->id,
            ];

            if ($currentUser && $currentUser->id === $u->id) {
                $myRankData = $item;
            }

            if ($rank <= 25) {
                $rankedList[] = $item;
            }
        }

        if (!$myRankData && $currentUser) {
            $score = (int)($currentUser->trust_score ?? 50);
            $tier = 'Bronze Reporter';
            if ($score >= 90) $tier = 'Platinum Reporter';
            elseif ($score >= 80) $tier = 'Gold Reporter';
            elseif ($score >= 65) $tier = 'Silver Reporter';

            $myRankData = [
                'rank'            => count($rankedList) + 1,
                'id'              => $currentUser->id,
                'name'            => $currentUser->name,
                'email'           => $currentUser->email,
                'trust_score'     => $score,
                'tier'            => $tier,
                'reports_count'   => $currentUser->reportedPrices()->count(),
                'is_current_user' => true,
            ];
        }

        return response([
            'my_stats'    => $myRankData,
            'leaderboard' => $rankedList,
        ], 200);
    }
}
