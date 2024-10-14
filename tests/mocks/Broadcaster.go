// Code generated by mockery. DO NOT EDIT.

package mocks

import (
	context "context"

	broadcaster "github.com/PredicateLabs/predicate-avs/core/broadcaster"

	mock "github.com/stretchr/testify/mock"

	policy "github.com/PredicateLabs/predicate-avs/core/policy"

	types "github.com/PredicateLabs/predicate-avs/core/types"
)

// Broadcaster is an autogenerated mock type for the Broadcaster type
type Broadcaster struct {
	mock.Mock
}

type Broadcaster_Expecter struct {
	mock *mock.Mock
}

func (_m *Broadcaster) EXPECT() *Broadcaster_Expecter {
	return &Broadcaster_Expecter{mock: &_m.Mock}
}

// Broadcast provides a mock function with given fields: ctx, task, _a2, metrics
func (_m *Broadcaster) Broadcast(ctx context.Context, task types.Task, _a2 policy.Policy, metrics broadcaster.Metrics) {
	_m.Called(ctx, task, _a2, metrics)
}

// Broadcaster_Broadcast_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'Broadcast'
type Broadcaster_Broadcast_Call struct {
	*mock.Call
}

// Broadcast is a helper method to define mock.On call
//   - ctx context.Context
//   - task types.Task
//   - _a2 policy.Policy
//   - metrics broadcaster.Metrics
func (_e *Broadcaster_Expecter) Broadcast(ctx interface{}, task interface{}, _a2 interface{}, metrics interface{}) *Broadcaster_Broadcast_Call {
	return &Broadcaster_Broadcast_Call{Call: _e.mock.On("Broadcast", ctx, task, _a2, metrics)}
}

func (_c *Broadcaster_Broadcast_Call) Run(run func(ctx context.Context, task types.Task, _a2 policy.Policy, metrics broadcaster.Metrics)) *Broadcaster_Broadcast_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context), args[1].(types.Task), args[2].(policy.Policy), args[3].(broadcaster.Metrics))
	})
	return _c
}

func (_c *Broadcaster_Broadcast_Call) Return() *Broadcaster_Broadcast_Call {
	_c.Call.Return()
	return _c
}

func (_c *Broadcaster_Broadcast_Call) RunAndReturn(run func(context.Context, types.Task, policy.Policy, broadcaster.Metrics)) *Broadcaster_Broadcast_Call {
	_c.Call.Return(run)
	return _c
}

// GetActiveOperators provides a mock function with given fields:
func (_m *Broadcaster) GetActiveOperators() []types.OperatorInfo {
	ret := _m.Called()

	if len(ret) == 0 {
		panic("no return value specified for GetActiveOperators")
	}

	var r0 []types.OperatorInfo
	if rf, ok := ret.Get(0).(func() []types.OperatorInfo); ok {
		r0 = rf()
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).([]types.OperatorInfo)
		}
	}

	return r0
}

// Broadcaster_GetActiveOperators_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'GetActiveOperators'
type Broadcaster_GetActiveOperators_Call struct {
	*mock.Call
}

// GetActiveOperators is a helper method to define mock.On call
func (_e *Broadcaster_Expecter) GetActiveOperators() *Broadcaster_GetActiveOperators_Call {
	return &Broadcaster_GetActiveOperators_Call{Call: _e.mock.On("GetActiveOperators")}
}

func (_c *Broadcaster_GetActiveOperators_Call) Run(run func()) *Broadcaster_GetActiveOperators_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run()
	})
	return _c
}

func (_c *Broadcaster_GetActiveOperators_Call) Return(_a0 []types.OperatorInfo) *Broadcaster_GetActiveOperators_Call {
	_c.Call.Return(_a0)
	return _c
}

func (_c *Broadcaster_GetActiveOperators_Call) RunAndReturn(run func() []types.OperatorInfo) *Broadcaster_GetActiveOperators_Call {
	_c.Call.Return(run)
	return _c
}

// Send provides a mock function with given fields: ctx, address, task
func (_m *Broadcaster) Send(ctx context.Context, address string, task types.Task) error {
	ret := _m.Called(ctx, address, task)

	if len(ret) == 0 {
		panic("no return value specified for Send")
	}

	var r0 error
	if rf, ok := ret.Get(0).(func(context.Context, string, types.Task) error); ok {
		r0 = rf(ctx, address, task)
	} else {
		r0 = ret.Error(0)
	}

	return r0
}

// Broadcaster_Send_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'Send'
type Broadcaster_Send_Call struct {
	*mock.Call
}

// Send is a helper method to define mock.On call
//   - ctx context.Context
//   - address string
//   - task types.Task
func (_e *Broadcaster_Expecter) Send(ctx interface{}, address interface{}, task interface{}) *Broadcaster_Send_Call {
	return &Broadcaster_Send_Call{Call: _e.mock.On("Send", ctx, address, task)}
}

func (_c *Broadcaster_Send_Call) Run(run func(ctx context.Context, address string, task types.Task)) *Broadcaster_Send_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context), args[1].(string), args[2].(types.Task))
	})
	return _c
}

func (_c *Broadcaster_Send_Call) Return(_a0 error) *Broadcaster_Send_Call {
	_c.Call.Return(_a0)
	return _c
}

func (_c *Broadcaster_Send_Call) RunAndReturn(run func(context.Context, string, types.Task) error) *Broadcaster_Send_Call {
	_c.Call.Return(run)
	return _c
}

// SetActiveOperators provides a mock function with given fields: operators
func (_m *Broadcaster) SetActiveOperators(operators []types.OperatorInfo) {
	_m.Called(operators)
}

// Broadcaster_SetActiveOperators_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'SetActiveOperators'
type Broadcaster_SetActiveOperators_Call struct {
	*mock.Call
}

// SetActiveOperators is a helper method to define mock.On call
//   - operators []types.OperatorInfo
func (_e *Broadcaster_Expecter) SetActiveOperators(operators interface{}) *Broadcaster_SetActiveOperators_Call {
	return &Broadcaster_SetActiveOperators_Call{Call: _e.mock.On("SetActiveOperators", operators)}
}

func (_c *Broadcaster_SetActiveOperators_Call) Run(run func(operators []types.OperatorInfo)) *Broadcaster_SetActiveOperators_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].([]types.OperatorInfo))
	})
	return _c
}

func (_c *Broadcaster_SetActiveOperators_Call) Return() *Broadcaster_SetActiveOperators_Call {
	_c.Call.Return()
	return _c
}

func (_c *Broadcaster_SetActiveOperators_Call) RunAndReturn(run func([]types.OperatorInfo)) *Broadcaster_SetActiveOperators_Call {
	_c.Call.Return(run)
	return _c
}

// NewBroadcaster creates a new instance of Broadcaster. It also registers a testing interface on the mock and a cleanup function to assert the mocks expectations.
// The first argument is typically a *testing.T value.
func NewBroadcaster(t interface {
	mock.TestingT
	Cleanup(func())
}) *Broadcaster {
	mock := &Broadcaster{}
	mock.Mock.Test(t)

	t.Cleanup(func() { mock.AssertExpectations(t) })

	return mock
}
