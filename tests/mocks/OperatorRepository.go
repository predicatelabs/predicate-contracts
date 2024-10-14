// Code generated by mockery. DO NOT EDIT.

package mocks

import (
	context "context"

	mock "github.com/stretchr/testify/mock"

	types "github.com/PredicateLabs/predicate-avs/core/types"
)

// OperatorRepository is an autogenerated mock type for the OperatorRepository type
type OperatorRepository struct {
	mock.Mock
}

type OperatorRepository_Expecter struct {
	mock *mock.Mock
}

func (_m *OperatorRepository) EXPECT() *OperatorRepository_Expecter {
	return &OperatorRepository_Expecter{mock: &_m.Mock}
}

// AddOperator provides a mock function with given fields: ctx, operator
func (_m *OperatorRepository) AddOperator(ctx context.Context, operator types.OperatorInfo) error {
	ret := _m.Called(ctx, operator)

	if len(ret) == 0 {
		panic("no return value specified for AddOperator")
	}

	var r0 error
	if rf, ok := ret.Get(0).(func(context.Context, types.OperatorInfo) error); ok {
		r0 = rf(ctx, operator)
	} else {
		r0 = ret.Error(0)
	}

	return r0
}

// OperatorRepository_AddOperator_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'AddOperator'
type OperatorRepository_AddOperator_Call struct {
	*mock.Call
}

// AddOperator is a helper method to define mock.On call
//   - ctx context.Context
//   - operator types.OperatorInfo
func (_e *OperatorRepository_Expecter) AddOperator(ctx interface{}, operator interface{}) *OperatorRepository_AddOperator_Call {
	return &OperatorRepository_AddOperator_Call{Call: _e.mock.On("AddOperator", ctx, operator)}
}

func (_c *OperatorRepository_AddOperator_Call) Run(run func(ctx context.Context, operator types.OperatorInfo)) *OperatorRepository_AddOperator_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context), args[1].(types.OperatorInfo))
	})
	return _c
}

func (_c *OperatorRepository_AddOperator_Call) Return(_a0 error) *OperatorRepository_AddOperator_Call {
	_c.Call.Return(_a0)
	return _c
}

func (_c *OperatorRepository_AddOperator_Call) RunAndReturn(run func(context.Context, types.OperatorInfo) error) *OperatorRepository_AddOperator_Call {
	_c.Call.Return(run)
	return _c
}

// ExpireOperators provides a mock function with given fields: ctx
func (_m *OperatorRepository) ExpireOperators(ctx context.Context) error {
	ret := _m.Called(ctx)

	if len(ret) == 0 {
		panic("no return value specified for ExpireOperators")
	}

	var r0 error
	if rf, ok := ret.Get(0).(func(context.Context) error); ok {
		r0 = rf(ctx)
	} else {
		r0 = ret.Error(0)
	}

	return r0
}

// OperatorRepository_ExpireOperators_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'ExpireOperators'
type OperatorRepository_ExpireOperators_Call struct {
	*mock.Call
}

// ExpireOperators is a helper method to define mock.On call
//   - ctx context.Context
func (_e *OperatorRepository_Expecter) ExpireOperators(ctx interface{}) *OperatorRepository_ExpireOperators_Call {
	return &OperatorRepository_ExpireOperators_Call{Call: _e.mock.On("ExpireOperators", ctx)}
}

func (_c *OperatorRepository_ExpireOperators_Call) Run(run func(ctx context.Context)) *OperatorRepository_ExpireOperators_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context))
	})
	return _c
}

func (_c *OperatorRepository_ExpireOperators_Call) Return(_a0 error) *OperatorRepository_ExpireOperators_Call {
	_c.Call.Return(_a0)
	return _c
}

func (_c *OperatorRepository_ExpireOperators_Call) RunAndReturn(run func(context.Context) error) *OperatorRepository_ExpireOperators_Call {
	_c.Call.Return(run)
	return _c
}

// GetAllOperatorInfo provides a mock function with given fields: ctx
func (_m *OperatorRepository) GetAllOperatorInfo(ctx context.Context) ([]types.OperatorInfo, error) {
	ret := _m.Called(ctx)

	if len(ret) == 0 {
		panic("no return value specified for GetAllOperatorInfo")
	}

	var r0 []types.OperatorInfo
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context) ([]types.OperatorInfo, error)); ok {
		return rf(ctx)
	}
	if rf, ok := ret.Get(0).(func(context.Context) []types.OperatorInfo); ok {
		r0 = rf(ctx)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).([]types.OperatorInfo)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context) error); ok {
		r1 = rf(ctx)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// OperatorRepository_GetAllOperatorInfo_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'GetAllOperatorInfo'
type OperatorRepository_GetAllOperatorInfo_Call struct {
	*mock.Call
}

// GetAllOperatorInfo is a helper method to define mock.On call
//   - ctx context.Context
func (_e *OperatorRepository_Expecter) GetAllOperatorInfo(ctx interface{}) *OperatorRepository_GetAllOperatorInfo_Call {
	return &OperatorRepository_GetAllOperatorInfo_Call{Call: _e.mock.On("GetAllOperatorInfo", ctx)}
}

func (_c *OperatorRepository_GetAllOperatorInfo_Call) Run(run func(ctx context.Context)) *OperatorRepository_GetAllOperatorInfo_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context))
	})
	return _c
}

func (_c *OperatorRepository_GetAllOperatorInfo_Call) Return(_a0 []types.OperatorInfo, _a1 error) *OperatorRepository_GetAllOperatorInfo_Call {
	_c.Call.Return(_a0, _a1)
	return _c
}

func (_c *OperatorRepository_GetAllOperatorInfo_Call) RunAndReturn(run func(context.Context) ([]types.OperatorInfo, error)) *OperatorRepository_GetAllOperatorInfo_Call {
	_c.Call.Return(run)
	return _c
}

// GetOperatorAddresses provides a mock function with given fields: ctx
func (_m *OperatorRepository) GetOperatorAddresses(ctx context.Context) ([]string, error) {
	ret := _m.Called(ctx)

	if len(ret) == 0 {
		panic("no return value specified for GetOperatorAddresses")
	}

	var r0 []string
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context) ([]string, error)); ok {
		return rf(ctx)
	}
	if rf, ok := ret.Get(0).(func(context.Context) []string); ok {
		r0 = rf(ctx)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).([]string)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context) error); ok {
		r1 = rf(ctx)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// OperatorRepository_GetOperatorAddresses_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'GetOperatorAddresses'
type OperatorRepository_GetOperatorAddresses_Call struct {
	*mock.Call
}

// GetOperatorAddresses is a helper method to define mock.On call
//   - ctx context.Context
func (_e *OperatorRepository_Expecter) GetOperatorAddresses(ctx interface{}) *OperatorRepository_GetOperatorAddresses_Call {
	return &OperatorRepository_GetOperatorAddresses_Call{Call: _e.mock.On("GetOperatorAddresses", ctx)}
}

func (_c *OperatorRepository_GetOperatorAddresses_Call) Run(run func(ctx context.Context)) *OperatorRepository_GetOperatorAddresses_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context))
	})
	return _c
}

func (_c *OperatorRepository_GetOperatorAddresses_Call) Return(_a0 []string, _a1 error) *OperatorRepository_GetOperatorAddresses_Call {
	_c.Call.Return(_a0, _a1)
	return _c
}

func (_c *OperatorRepository_GetOperatorAddresses_Call) RunAndReturn(run func(context.Context) ([]string, error)) *OperatorRepository_GetOperatorAddresses_Call {
	_c.Call.Return(run)
	return _c
}

// GetOperatorInfo provides a mock function with given fields: ctx, address
func (_m *OperatorRepository) GetOperatorInfo(ctx context.Context, address string) (types.OperatorInfo, error) {
	ret := _m.Called(ctx, address)

	if len(ret) == 0 {
		panic("no return value specified for GetOperatorInfo")
	}

	var r0 types.OperatorInfo
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, string) (types.OperatorInfo, error)); ok {
		return rf(ctx, address)
	}
	if rf, ok := ret.Get(0).(func(context.Context, string) types.OperatorInfo); ok {
		r0 = rf(ctx, address)
	} else {
		r0 = ret.Get(0).(types.OperatorInfo)
	}

	if rf, ok := ret.Get(1).(func(context.Context, string) error); ok {
		r1 = rf(ctx, address)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// OperatorRepository_GetOperatorInfo_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'GetOperatorInfo'
type OperatorRepository_GetOperatorInfo_Call struct {
	*mock.Call
}

// GetOperatorInfo is a helper method to define mock.On call
//   - ctx context.Context
//   - address string
func (_e *OperatorRepository_Expecter) GetOperatorInfo(ctx interface{}, address interface{}) *OperatorRepository_GetOperatorInfo_Call {
	return &OperatorRepository_GetOperatorInfo_Call{Call: _e.mock.On("GetOperatorInfo", ctx, address)}
}

func (_c *OperatorRepository_GetOperatorInfo_Call) Run(run func(ctx context.Context, address string)) *OperatorRepository_GetOperatorInfo_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context), args[1].(string))
	})
	return _c
}

func (_c *OperatorRepository_GetOperatorInfo_Call) Return(_a0 types.OperatorInfo, _a1 error) *OperatorRepository_GetOperatorInfo_Call {
	_c.Call.Return(_a0, _a1)
	return _c
}

func (_c *OperatorRepository_GetOperatorInfo_Call) RunAndReturn(run func(context.Context, string) (types.OperatorInfo, error)) *OperatorRepository_GetOperatorInfo_Call {
	_c.Call.Return(run)
	return _c
}

// TestConnection provides a mock function with given fields: ctx
func (_m *OperatorRepository) TestConnection(ctx context.Context) error {
	ret := _m.Called(ctx)

	if len(ret) == 0 {
		panic("no return value specified for TestConnection")
	}

	var r0 error
	if rf, ok := ret.Get(0).(func(context.Context) error); ok {
		r0 = rf(ctx)
	} else {
		r0 = ret.Error(0)
	}

	return r0
}

// OperatorRepository_TestConnection_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'TestConnection'
type OperatorRepository_TestConnection_Call struct {
	*mock.Call
}

// TestConnection is a helper method to define mock.On call
//   - ctx context.Context
func (_e *OperatorRepository_Expecter) TestConnection(ctx interface{}) *OperatorRepository_TestConnection_Call {
	return &OperatorRepository_TestConnection_Call{Call: _e.mock.On("TestConnection", ctx)}
}

func (_c *OperatorRepository_TestConnection_Call) Run(run func(ctx context.Context)) *OperatorRepository_TestConnection_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(context.Context))
	})
	return _c
}

func (_c *OperatorRepository_TestConnection_Call) Return(_a0 error) *OperatorRepository_TestConnection_Call {
	_c.Call.Return(_a0)
	return _c
}

func (_c *OperatorRepository_TestConnection_Call) RunAndReturn(run func(context.Context) error) *OperatorRepository_TestConnection_Call {
	_c.Call.Return(run)
	return _c
}

// NewOperatorRepository creates a new instance of OperatorRepository. It also registers a testing interface on the mock and a cleanup function to assert the mocks expectations.
// The first argument is typically a *testing.T value.
func NewOperatorRepository(t interface {
	mock.TestingT
	Cleanup(func())
}) *OperatorRepository {
	mock := &OperatorRepository{}
	mock.Mock.Test(t)

	t.Cleanup(func() { mock.AssertExpectations(t) })

	return mock
}
